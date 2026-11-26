# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class ProcessDeliveryOutboxTest < Minitest::Test
  class Repository
    attr_reader :claimed, :delivered, :failed, :expired_call, :calls

    def initialize(entries, expired: 0)
      @entries = entries
      @claimed = false
      @expired = expired
      @calls = []
    end

    def expire_stale(older_than:, now:, lease_seconds:)
      @calls << :expire_stale
      @expired_call = {older_than: older_than, now: now, lease_seconds: lease_seconds}
      @expired
    end

    def claim_due(limit:, now:, lease_seconds:)
      @calls << :claim_due
      @claimed = [limit, now, lease_seconds]
      @entries
    end

    def mark_delivered(**attributes)
      @delivered = attributes
    end

    def mark_failed(**attributes)
      @failed = attributes
    end
  end

  class Dispatcher
    attr_reader :request

    def initialize(error: nil)
      @error = error
    end

    def call(request:)
      @request = request
      raise @error if @error
      :ok
    end
  end

  def setup
    @now = Time.utc(2026, 9, 14, 3)
    @request = build_request
    @entry = PrismHub::Domain::DeliveryOutboxEntry.new(
      id: "entry-1",
      workspace: "personal",
      channel: "digest",
      idempotency_key: @request.idempotency_key,
      intent_payload: @request.to_h,
      status: "processing",
      attempts: 1,
      available_at: @now,
      locked_at: @now,
      lock_token: "a" * 64
    )
  end

  def test_dispatches_the_persisted_request_and_marks_delivery
    repository = Repository.new([@entry])
    dispatcher = Dispatcher.new
    processor = PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: repository,
      dispatch_delivery: dispatcher,
      clock: -> { @now }
    )

    processor.call(limit: 1, lease_seconds: 300)

    assert_equal @request.to_h, dispatcher.request.to_h
    assert_equal({id: "entry-1", lock_token: "a" * 64, delivered_at: @now}, repository.delivered)
    assert_nil repository.failed
  end

  def test_a_delivered_board_records_the_message_it_lives_in
    view = PrismHub::Domain::DeliveryView.new(silent: true, slot: "board", revision: 4)
    request = PrismHub::Domain::DeliveryRequest.new(
      artifact: @request.artifact, routes: @request.routes, workspace: "personal", channel: "digest",
      idempotency_key: @request.idempotency_key, view: view
    )
    entry = PrismHub::Domain::DeliveryOutboxEntry.new(
      id: "entry-2", workspace: "personal", channel: "digest", idempotency_key: request.idempotency_key,
      intent_payload: request.to_h, status: "processing", attempts: 1, available_at: @now, locked_at: @now,
      lock_token: "b" * 64
    )
    dispatcher = Object.new
    dispatcher.define_singleton_method(:call) { |request:| [{"provider_message_id" => 501}] }
    receipts = []
    recorder = Object.new
    recorder.define_singleton_method(:record) { |**receipt| receipts << receipt }

    PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: Repository.new([entry]), dispatch_delivery: dispatcher, clock: -> { @now },
      view_receipts: recorder
    ).call(limit: 1, lease_seconds: 300)

    assert_equal [{workspace: "personal", slot: "board", revision: 4, message_id: 501}], receipts
  end

  def test_transient_delivery_failure_schedules_retry
    error = PrismHub::ExecutionUnavailableError.new(
      "hub.bot.delivery.unavailable",
      "unavailable"
    )
    repository = Repository.new([@entry])
    processor = PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: repository,
      dispatch_delivery: Dispatcher.new(error: error),
      clock: -> { @now }
    )

    processor.call(limit: 1, lease_seconds: 300)

    assert_equal "hub.bot.delivery.unavailable", repository.failed[:error_code]
    assert_equal @now + 30, repository.failed[:retry_at]
  end

  def test_rate_limit_retry_uses_provider_delay
    error = PrismHub::ExecutionUnavailableError.new(
      "hub.bot.delivery.rate_limited",
      "rate limited",
      details: {"retry_after_seconds" => 17}
    )
    repository = Repository.new([@entry])
    processor = PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: repository,
      dispatch_delivery: Dispatcher.new(error: error),
      clock: -> { @now }
    )

    processor.call(limit: 1, lease_seconds: 300)

    assert_equal @now + 17, repository.failed[:retry_at]
  end

  def test_a_notification_older_than_six_hours_is_retired_before_anything_is_claimed
    repository = Repository.new([@entry])
    processor = PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: repository, dispatch_delivery: Dispatcher.new, clock: -> { @now }
    )

    processor.call(limit: 1, lease_seconds: 300)

    assert_equal [:expire_stale, :claim_due], repository.calls
    assert_equal({older_than: @now - 6 * 60 * 60, now: @now, lease_seconds: 300}, repository.expired_call)
  end

  def test_the_maximum_age_is_configurable_and_must_be_positive
    repository = Repository.new([])
    PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: repository, dispatch_delivery: Dispatcher.new, clock: -> { @now }, max_age_seconds: 900
    ).call(limit: 1, lease_seconds: 300)
    assert_equal @now - 900, repository.expired_call[:older_than]

    assert_raises(PrismHub::ConfigurationError) do
      PrismHub::UseCases::ProcessDeliveryOutbox.new(
        outbox_repository: repository, dispatch_delivery: Dispatcher.new, max_age_seconds: 0
      )
    end
  end

  def test_retiring_notifications_is_logged_with_the_count_and_never_when_there_is_nothing_to_retire
    output = StringIO.new
    logger = Logger.new(output)
    build = ->(expired) do
      PrismHub::UseCases::ProcessDeliveryOutbox.new(
        outbox_repository: Repository.new([], expired: expired), dispatch_delivery: Dispatcher.new,
        clock: -> { @now }, logger: logger
      )
    end

    build.call(0).call(limit: 1, lease_seconds: 300)
    assert_equal "", output.string

    build.call(42).call(limit: 1, lease_seconds: 300)
    assert_includes output.string, '"event":"hub.delivery.expired"'
    assert_includes output.string, '"count":42'
    assert_includes output.string, '"max_age_seconds":21600'
  end

  private

  def build_request
    PrismHub::Domain::DeliveryRequest.new(
      artifact: {"artifact_id" => "artifact-1", "artifact_kind" => "mail.digest", "payload" => {"a" => 1}},
      routes: [{"artifact_kind" => "mail.digest",
                "logical_context" => {"workspace" => "personal", "channel" => "digest"}}],
      workspace: "personal",
      channel: "digest",
      idempotency_key: Digest::SHA256.hexdigest("artifact-1")
    )
  end
end
