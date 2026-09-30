# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

# The whole loop against the real repositories, with only the two subprocesses faked.
class IngestSignalsTest < Minitest::Test
  NOW = Time.utc(2026, 9, 30, 12, 0, 0)
  CELL = "861e68697ffffff".freeze
  SOURCE = PrismHub::Domain::SignalSource.new(kind: "telegram", channel: "vanek_nikolaev")
  ASSESSMENT_ID = "fusion.v1/drone/geonames:703448/vanek_nikolaev/100".freeze

  class Gateway < PrismHub::Ports::SignalGateway
    attr_accessor :pages, :assessed, :poll_error
    attr_reader :afters, :windows

    def initialize
      @pages = []
      @afters = []
      @windows = []
      @assessed = Assessed.new(assessments: [], events: [])
    end

    def poll(source:, after:)
      @afters << after
      raise @poll_error if @poll_error

      Polled.new(evidence: @pages.shift || [])
    end

    def assess(evidence:, evaluation_time:)
      @windows << evidence.map { |item| item["external_id"] }
      @assessed
    end
  end

  def setup
    clear_tables
    identities = PrismHub::Adapters::ActiveRecordUserIdentityRepository.new
    memberships = PrismHub::Adapters::ActiveRecordWorkspaceMembershipRepository.new
    @subscriptions = PrismHub::Adapters::ActiveRecordAlertSubscriptionRepository.new
    PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(identifier: "personal-a", status: "active")
    @owner = identities.provision(canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0xuser-a"))
    memberships.grant(user_identity: @owner, workspace_id: "personal-a", role: "owner")
    @subscriptions.save(
      workspace_id: "personal-a", actor_user_identity_id: @owner.id, cell: CELL,
      categories: %w[drone], include_nearby: true, occurred_at: NOW
    )
    @window = PrismHub::Adapters::ActiveRecordSignalWindowRepository.new
    @ledger = PrismHub::Adapters::ActiveRecordSignalAlertLedger.new
    @gateway = Gateway.new
    @logger = Logger.new(File::NULL)
    @ingest = build_ingest
  end

  def teardown
    clear_tables
  end

  def test_a_report_becomes_one_queued_alert_and_a_rerun_adds_nothing
    bind_chat
    @gateway.pages = [[item(100, "шахеди на Київ")]]
    @gateway.assessed = assessed(status: "active")

    first = @ingest.call(now: NOW)
    second = @ingest.call(now: NOW + 60)

    assert_equal 1, first.summary.alerts
    assert_equal 0, second.summary.alerts
    entries = PrismHub::Adapters::ActiveRecordRecords::DeliveryOutboxEntry.all.to_a
    assert_equal 1, entries.length
    assert_equal "personal-a", entries.first.workspace
    assert_equal "alerts", entries.first.logical_channel
    assert_equal "signal.alert", entries.first.intent_payload.dig("artifact", "artifact_kind")
  end

  def test_the_cursor_advances_and_the_next_poll_resumes_from_it
    @gateway.pages = [[item(100, "a"), item(103, "b")], []]

    @ingest.call(now: NOW)
    @ingest.call(now: NOW + 60)

    assert_equal [nil, "103"], @gateway.afters
    assert_equal "103", @window.cursor(source_id: SOURCE.id)
  end

  def test_the_cursor_never_moves_backwards
    @gateway.pages = [[item(103, "b")], [item(101, "a")]]

    @ingest.call(now: NOW)
    @ingest.call(now: NOW + 60)

    assert_equal "103", @window.cursor(source_id: SOURCE.id)
  end

  def test_an_unreadable_source_does_not_stop_the_pass
    @gateway.pages = [[item(100, "a")]]
    @ingest.call(now: NOW)
    @gateway.poll_error = PrismHub::ExecutionUnavailableError.new("hub.signal.collector.timeout", "slow")
    @gateway.assessed = assessed(status: "active")
    bind_chat

    result = @ingest.call(now: NOW + 60)

    assert_equal [SOURCE.id], result.failed_sources
    assert_equal 1, result.summary.alerts
    assert_equal [["vanek_nikolaev/100"], ["vanek_nikolaev/100"]], @gateway.windows
  end

  def test_the_window_holds_only_what_is_recent_enough
    @gateway.pages = [[item(100, "old", at: NOW - 5 * 3600), item(101, "recent", at: NOW - 60)]]

    @ingest.call(now: NOW)

    assert_equal [["vanek_nikolaev/101"]], @gateway.windows
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::SignalEvidence.count
  end

  def test_the_ledger_is_pruned_after_its_retention
    @ledger.record(assessment_id: "old", workspace_id: "personal-a", hazard_class: "drone", kind: "alert", event_seq: 1, at: NOW - 2 * 86_400)

    @ingest.call(now: NOW)

    refute @ledger.recorded?(assessment_id: "old", workspace_id: "personal-a", kind: "alert")
  end

  private

  def build_ingest
    fan_out = PrismHub::UseCases::FanOutSignalEvents.new(
      subscription_repository: @subscriptions,
      ledger: @ledger,
      binding_repository: PrismHub::Adapters::ActiveRecordTelegramSurfaceBindingRepository.new,
      outbox_repository: PrismHub::Adapters::ActiveRecordDeliveryOutboxRepository.new,
      logger: @logger
    )
    PrismHub::UseCases::IngestSignals.new(
      sources: [SOURCE], gateway: @gateway, window_repository: @window, ledger: @ledger,
      fan_out: fan_out, logger: @logger
    )
  end

  def bind_chat
    principal = PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal.create!(identifier: "telegram-bot", status: "active")
    bot = PrismHub::Adapters::ActiveRecordBotInstanceRepository.new.ensure(
      principal_id: principal.identifier, workspace_id: "personal-a",
      actor_user_identity_id: @owner.id, occurred_at: NOW
    )
    PrismHub::Adapters::ActiveRecordTelegramSurfaceBindingRepository.new.bind(
      workspace_id: "personal-a", bot_instance_id: bot.id, logical_channel: "alerts",
      chat_id: 42, message_thread_id: nil, actor_user_identity_id: @owner.id
    )
  end

  def item(number, text, at: NOW - 60)
    {
      "source_id" => SOURCE.id, "external_id" => "vanek_nikolaev/#{number}",
      "published_at" => at.iso8601, "text" => text
    }
  end

  def assessed(status:)
    assessment = {
      "assessment_id" => ASSESSMENT_ID, "class" => "drone", "kinds" => ["air.attack_drone"],
      "place" => {"id" => "geonames:703448", "name" => "Київ"}, "proximity" => "target",
      "cells" => {"resolution" => 6, "cells" => [CELL]},
      "valid_from" => (NOW - 60).iso8601, "valid_until" => (NOW + 1800).iso8601,
      "status" => status, "likelihood" => "moderate",
      "evidence" => [{"source_id" => SOURCE.id, "evidence_id" => "vanek_nikolaev/100", "url" => "https://t.me/vanek_nikolaev/100", "observed_at" => (NOW - 60).iso8601}]
    }
    event = {"assessment_id" => ASSESSMENT_ID, "seq" => 1, "kind" => "issued", "effective_at" => (NOW - 60).iso8601}
    PrismHub::Ports::SignalGateway::Assessed.new(assessments: [assessment], events: [event])
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
      delivery_outbox_entries signal_alert_deliveries signal_evidence signal_source_cursors
      telegram_surface_bindings bot_instance_lifecycle_events bot_instances service_principals alert_subscriptions
      workspace_memberships provider_identity_bindings user_identities workspaces
    ].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
