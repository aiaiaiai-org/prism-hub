# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordSignalThreatRegistryTest < Minitest::Test
  T0 = Time.utc(2026, 10, 23, 5, 0)
  ASSESSMENT = "fusion.v1/drone/geonames:703448/war_monitor/100".freeze

  def setup
    @registry = PrismHub::Adapters::ActiveRecordSignalThreatRegistry.new
    records.delete_all
  end

  def teardown
    records.delete_all
  end

  def test_a_report_registers_once_with_a_durable_identifier_a_named_place_and_provenance
    assert_equal 1, @registry.sync(assessments: [assessment], now: T0)
    record = records.find_by!(assessment_id: ASSESSMENT)
    id = record.id
    assert_match(/\A[0-9a-f-]{36}\z/, id)
    assert_equal "drone", record.hazard_class
    assert_equal %w[air.attack_drone], record.hazard_kinds
    assert_equal "geonames:703448", record.destination_id
    assert_equal "Київ", record.destination_name
    assert_equal T0 - 60, record.first_reported_at
    assert_equal T0 - 60, record.last_reported_at
    assert_equal "active", record.status
    assert_equal ["telegram.channel:war_monitor"], record.source_reports.map { |source| source.fetch("source_id") }
    assert_equal ["telegram.channel:war_monitor"], record.active_sources
    assert_kind_of Array, record.source_reports
    assert_nil record.reported_arrival_from
    assert_nil record.reported_arrival_until
    assert_nil record.arrival_source_url

    @registry.sync(assessments: [assessment], now: T0 + 60)
    assert_equal 1, records.count
    assert_equal id, records.first.id
    assert_equal 1, records.first.source_reports.length
  end

  def test_two_sources_keep_distinct_reports_and_do_not_get_weighted_by_name
    later = assessment
    later["evidence"] << evidence("kpszsu", 101, T0)
    later["active_sources"] = %w[telegram.channel:war_monitor telegram.channel:kpszsu]
    later["valid_until"] = (T0 + 1800).iso8601
    @registry.sync(assessments: [later], now: T0 + 60)

    result = records.first
    assert_equal ["telegram.channel:war_monitor", "telegram.channel:kpszsu"].sort,
      result.source_reports.map { |source| source.fetch("source_id") }.sort
    assert_equal T0, result.last_reported_at
    assert_equal %w[telegram.channel:kpszsu telegram.channel:war_monitor], result.active_sources
    assert_equal ASSESSMENT, result.assessment_id
  end

  def test_expiry_is_not_a_claim_of_all_clear
    @registry.sync(assessments: [assessment], now: T0)
    @registry.sync(assessments: [], now: T0 + 1900)

    record = records.first
    assert_equal "expired", record.status
    assert_equal [], record.active_sources
    assert_equal T0 - 60, record.first_reported_at
    assert_nil record.reported_arrival_from
  end

  def test_retracted_incident_is_not_reopened_by_a_stale_window
    @registry.sync(assessments: [assessment], now: T0)
    cancelled = assessment
    cancelled["status"] = "retracted"
    cancelled["active_sources"] = []
    @registry.sync(assessments: [cancelled], now: T0 + 60)
    @registry.sync(assessments: [assessment], now: T0 + 120)
    assert_equal "retracted", records.first.status
    assert_equal [], records.first.active_sources
    assert_equal 1, records.first.source_reports.length
  end


  def test_source_history_survives_a_partial_clear_but_active_sources_change
    initial = assessment
    initial["evidence"] << evidence("kpszsu", 2, T0)
    initial["active_sources"] = ["telegram.channel:kpszsu", "telegram.channel:war_monitor"]
    @registry.sync(assessments: [initial], now: T0)

    after_clear = assessment
    after_clear["evidence"] << evidence("kpszsu", 2, T0)
    after_clear["active_sources"] = ["telegram.channel:war_monitor"]
    @registry.sync(assessments: [after_clear], now: T0 + 60)

    record = records.first
    assert_equal 2, record.source_reports.size
    assert_equal ["telegram.channel:war_monitor"], record.active_sources
    assert_equal "active", record.status
  end

  def test_older_runtime_reports_unknown_active_sources_instead_of_zero
    old = assessment
    old.delete("active_sources")
    @registry.sync(assessments: [old], now: T0)
    assert_nil records.first.active_sources

    fresh = assessment
    @registry.sync(assessments: [fresh], now: T0 + 60)
    assert_equal ["telegram.channel:war_monitor"], records.first.active_sources

    @registry.sync(assessments: [old], now: T0 + 120)
    assert_nil records.first.active_sources
  end

  def test_a_source_must_be_cited_before_it_can_be_live
    invalid = assessment
    invalid["active_sources"] = ["telegram.channel:kpszsu"]
    assert_raises(ArgumentError) { @registry.sync(assessments: [invalid], now: T0) }
    assert_equal 0, records.count
  end

  def test_active_sources_must_agree_with_terminal_state
    bad = assessment
    bad["status"] = "retracted"
    assert_raises(ArgumentError) { @registry.sync(assessments: [bad], now: T0) }
    assert_equal 0, records.count
  end

  def test_database_enforces_json_array_shape_for_reports
    @registry.sync(assessments: [assessment], now: T0)
    record = records.first
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction(requires_new: true) { record.update_columns(source_reports: {}) }
    end
  end

  def test_exact_coordinates_are_never_recorded_as_a_named_destination
    wrong = assessment
    wrong["place"] = {"id" => "geonames:703448", "name" => "Київ", "lat" => 50.45}
    assert_raises(ArgumentError) { @registry.sync(assessments: [wrong], now: T0) }
    assert_equal 0, records.count
  end

  private

  def records
    PrismHub::Adapters::ActiveRecordRecords::SignalThreatRecord
  end

  def evidence(source, number, at)
    {
      "source_id" => "telegram.channel:#{source}",
      "evidence_id" => "#{source}/#{number}",
      "url" => "https://t.me/#{source}/#{number}",
      "observed_at" => at.iso8601
    }
  end

  def assessment
    {
      "assessment_id" => ASSESSMENT,
      "class" => "drone",
      "kinds" => ["air.attack_drone"],
      "place" => {"id" => "geonames:703448", "name" => "Київ"},
      "status" => "active",
      "valid_from" => (T0 - 60).iso8601,
      "valid_until" => (T0 + 1800).iso8601,
      "evidence" => [evidence("war_monitor", 100, T0 - 60)],
      "active_sources" => ["telegram.channel:war_monitor"]
    }
  end
end
