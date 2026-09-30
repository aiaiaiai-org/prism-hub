# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class FanOutSignalEventsTest < Minitest::Test
  NOW = Time.utc(2026, 9, 30, 12, 0, 0)
  KYIV = "861e68697ffffff".freeze
  ELSEWHERE = "8601aa26fffffff".freeze
  ID = "fusion.v1/drone/geonames:703448/vanek_nikolaev/100".freeze

  class Subscriptions
    def initialize(list)
      @list = list
    end

    def covering(cells:, category:)
      @list.select { |s| cells.include?(s.cell) && s.categories.include?(category) }
    end

    def find_all(workspace_ids:)
      @list.select { |s| workspace_ids.include?(s.workspace_id) }
    end

    def remove(workspace)
      @list.reject! { |s| s.workspace_id == workspace }
    end
  end

  class Ledger
    attr_reader :rows

    def initialize
      @rows = []
    end

    def recorded?(assessment_id:, workspace_id:, kind:)
      @rows.any? { |r| r[:assessment_id] == assessment_id && r[:workspace_id] == workspace_id && r[:kind] == kind }
    end

    def recent_alert?(workspace_id:, hazard_class:, since:)
      @rows.any? { |r| r[:workspace_id] == workspace_id && r[:hazard_class] == hazard_class && r[:kind] == "alert" && r[:at] >= since }
    end

    def record(**row)
      return false if recorded?(assessment_id: row[:assessment_id], workspace_id: row[:workspace_id], kind: row[:kind])

      @rows << row
      true
    end

    def alerted_workspaces(assessment_id:)
      @rows.select { |r| r[:assessment_id] == assessment_id && r[:kind] == "alert" }.map { |r| r[:workspace_id] }
    end
  end

  class Bindings
    def initialize(workspaces)
      @workspaces = workspaces
    end

    def find_by_logical_context(workspace_id:, logical_channel:)
      logical_channel == "alerts" && @workspaces.include?(workspace_id) ? :binding : nil
    end
  end

  class Outbox
    attr_reader :requests
    attr_accessor :error

    def initialize
      @requests = []
    end

    def enqueue(request:, available_at:)
      raise @error if @error

      @requests << request
    end
  end

  def setup
    @ledger = Ledger.new
    @outbox = Outbox.new
    @subscriptions = Subscriptions.new([subscription("ws-a", KYIV), subscription("ws-b", ELSEWHERE)])
    @bound = %w[ws-a ws-b]
  end

  def test_an_alert_reaches_only_people_standing_in_the_cells
    summary = fan_out([assessment], [event("issued", 1)])

    assert_equal 1, summary.alerts
    assert_equal ["ws-a"], @outbox.requests.map(&:workspace)
    request = @outbox.requests.first
    assert_equal "alerts", request.channel
    assert_equal "signal.alert", request.artifact.fetch("artifact_kind")
    payload = request.artifact.fetch("payload")
    assert_equal "prism-hub.signal-alert.v1", payload.fetch("schema_version")
    assert_equal "alert", payload.fetch("event")
    assert_equal (NOW - 60).iso8601, payload.fetch("event_at")
    assert_equal "Київ", payload.dig("place", "name")
    assert_equal "drone", payload.dig("hazard", "class")
    assert_equal "https://t.me/vanek_nikolaev/100", payload.fetch("sources").last.fetch("url")
  end

  def test_the_message_carries_no_position
    fan_out([assessment], [event("issued", 1)])

    serialised = JSON.generate(@outbox.requests.first.to_h)
    refute_includes serialised, KYIV
    refute_includes serialised, "cells"
  end

  def test_a_person_who_did_not_ask_for_the_class_is_not_told
    @subscriptions = Subscriptions.new([subscription("ws-a", KYIV, categories: %w[missile])])

    summary = fan_out([assessment], [event("issued", 1)])

    assert_equal 0, summary.alerts
    assert_empty @outbox.requests
  end

  def test_nearby_reports_respect_the_nearby_switch
    @subscriptions = Subscriptions.new([
      subscription("ws-a", KYIV, include_nearby: false),
      subscription("ws-b", KYIV, include_nearby: true)
    ])

    summary = fan_out([assessment(proximity: "nearby")], [event("issued", 1)])

    assert_equal ["ws-b"], @outbox.requests.map(&:workspace)
    assert_equal 1, summary.skipped[:nearby_off]
  end

  def test_a_target_report_ignores_the_nearby_switch
    @subscriptions = Subscriptions.new([subscription("ws-a", KYIV, include_nearby: false)])

    fan_out([assessment(proximity: "target")], [event("issued", 1)])

    assert_equal ["ws-a"], @outbox.requests.map(&:workspace)
  end

  def test_a_renewal_does_not_tell_the_same_person_again
    fan_out([assessment], [event("issued", 1)])
    summary = fan_out([assessment], [event("issued", 1), event("superseded", 2)])

    assert_equal 1, @outbox.requests.length
    assert_equal 0, summary.alerts
    assert_equal 2, summary.skipped[:already_told]
  end

  def test_a_renewal_tells_someone_who_was_not_told_before
    @subscriptions = Subscriptions.new([])
    fan_out([assessment], [event("issued", 1)])
    @subscriptions = Subscriptions.new([subscription("ws-a", KYIV)])

    fan_out([assessment], [event("superseded", 2)])

    assert_equal ["ws-a"], @outbox.requests.map(&:workspace)
  end

  def test_the_cooldown_holds_back_a_second_report_of_the_same_class
    other = assessment(id: "fusion.v1/drone/geonames:1/vanek_nikolaev/101", place: "Бориспіль")

    summary = fan_out([assessment, other], [event("issued", 1), event("issued", 1, id: other.fetch("assessment_id"), at: NOW - 30)])

    assert_equal 1, summary.alerts
    assert_equal 1, summary.skipped[:cooldown]
  end

  def test_the_cooldown_is_per_class
    missile = assessment(id: "fusion.v1/missile/geonames:703448/vanek_nikolaev/101", hazard: "missile")
    @subscriptions = Subscriptions.new([subscription("ws-a", KYIV, categories: %w[drone missile])])

    summary = fan_out([assessment, missile], [event("issued", 1), event("issued", 1, id: missile.fetch("assessment_id"), at: NOW - 30)])

    assert_equal 2, summary.alerts
  end

  def test_the_cooldown_lapses
    fan_out([assessment], [event("issued", 1)])
    later = NOW + 600
    other = assessment(id: "fusion.v1/drone/geonames:1/vanek_nikolaev/101", place: "Бориспіль", valid_until: later + 1800)

    summary = fan_out([other], [event("issued", 1, id: other.fetch("assessment_id"), at: later - 10)], now: later)

    assert_equal 1, summary.alerts
  end

  def test_an_expired_or_retracted_assessment_is_not_announced
    assert_equal 0, fan_out([assessment(status: "expired")], [event("issued", 1)]).alerts
    assert_equal 0, fan_out([assessment(status: "retracted")], [event("issued", 1)]).alerts
    assert_equal 0, fan_out([assessment(valid_until: NOW - 1)], [event("issued", 1)]).alerts
    assert_empty @outbox.requests
  end

  def test_history_is_not_news
    old = event("issued", 1, at: NOW - 1801)

    summary = fan_out([assessment], [old])

    assert_equal 0, summary.alerts
    assert_empty @outbox.requests
  end

  def test_an_expiry_says_nothing
    fan_out([assessment], [event("issued", 1)])
    @outbox.requests.clear

    summary = fan_out([assessment(status: "expired")], [event("expired", 3, at: NOW)])

    assert_equal 0, summary.retractions
    assert_empty @outbox.requests
  end

  def test_a_retraction_reaches_only_people_who_were_told
    @subscriptions = Subscriptions.new([subscription("ws-a", KYIV), subscription("ws-b", KYIV)])
    fan_out([assessment], [event("issued", 1)], only: %w[ws-a])
    @outbox.requests.clear

    summary = fan_out([assessment(status: "retracted")], [event("retracted", 2, at: NOW + 60)], now: NOW + 60)

    assert_equal 1, summary.retractions
    assert_equal ["ws-a"], @outbox.requests.map(&:workspace)
    payload = @outbox.requests.first.artifact.fetch("payload")
    assert_equal "retraction", payload.fetch("event")
    assert_equal "https://t.me/vanek_nikolaev/101", payload.fetch("event_url")
    assert_empty payload.fetch("still_active")
  end

  def test_a_retraction_is_sent_once
    fan_out([assessment], [event("issued", 1)])
    retraction = [event("retracted", 2, at: NOW + 60)]
    fan_out([assessment(status: "retracted")], retraction, now: NOW + 60)
    summary = fan_out([assessment(status: "retracted")], retraction, now: NOW + 90)

    assert_equal 2, @outbox.requests.length
    assert_equal 1, summary.skipped[:already_retracted]
  end

  def test_a_retraction_is_not_sent_to_someone_who_stopped
    fan_out([assessment], [event("issued", 1)])
    @subscriptions.remove("ws-a")
    @outbox.requests.clear

    summary = fan_out([assessment(status: "retracted")], [event("retracted", 2, at: NOW + 60)], now: NOW + 60)

    assert_equal 0, summary.retractions
    assert_equal 1, summary.skipped[:unsubscribed]
    assert_empty @outbox.requests
  end

  def test_a_retraction_names_other_reports_that_still_cover_the_person
    fan_out([assessment], [event("issued", 1)])
    @outbox.requests.clear
    still = assessment(id: "fusion.v1/drone/geonames:2/vanek_nikolaev/101", place: "Бровари")
    unrelated = assessment(id: "fusion.v1/drone/geonames:3/vanek_nikolaev/102", place: "Львів", cells: [ELSEWHERE])
    other_class = assessment(id: "fusion.v1/missile/geonames:4/vanek_nikolaev/103", place: "Ірпінь", hazard: "missile")

    fan_out(
      [assessment(status: "retracted"), still, unrelated, other_class],
      [event("retracted", 2, at: NOW + 60)],
      now: NOW + 60
    )

    assert_equal ["Бровари"], @outbox.requests.first.artifact.fetch("payload").fetch("still_active")
  end

  def test_a_retraction_ignores_reports_that_lapsed
    fan_out([assessment], [event("issued", 1)])
    @outbox.requests.clear
    lapsed = assessment(id: "fusion.v1/drone/geonames:2/vanek_nikolaev/101", place: "Бровари", status: "expired")

    fan_out([assessment(status: "retracted"), lapsed], [event("retracted", 2, at: NOW + 60)], now: NOW + 60)

    assert_empty @outbox.requests.first.artifact.fetch("payload").fetch("still_active")
  end

  def test_nobody_is_queued_without_a_bound_chat
    @bound = []

    summary = fan_out([assessment], [event("issued", 1)])

    assert_equal 0, summary.alerts
    assert_equal 1, summary.skipped[:no_surface]
    assert_empty @ledger.rows
  end

  def test_one_failure_does_not_silence_the_others
    @subscriptions = Subscriptions.new([subscription("ws-a", KYIV), subscription("ws-b", KYIV)])
    outbox = Object.new
    calls = 0
    outbox.define_singleton_method(:enqueue) do |request:, available_at:|
      calls += 1
      raise PrismHub::InputError.new("hub.test", "boom") if calls == 1
    end
    @outbox = outbox

    summary = fan_out([assessment], [event("issued", 1)])

    assert_equal 1, summary.alerts
    assert_equal 1, summary.skipped[:failed]
    assert_equal ["ws-b"], @ledger.rows.map { |r| r[:workspace_id] }
  end

  def test_a_failed_delivery_is_tried_again_on_the_next_pass
    @outbox.error = PrismHub::InputError.new("hub.test", "boom")
    fan_out([assessment], [event("issued", 1)])
    assert_empty @ledger.rows

    @outbox.error = nil
    summary = fan_out([assessment], [event("issued", 1)], now: NOW + 60)

    assert_equal 1, summary.alerts
  end

  def test_the_idempotency_key_is_per_person_per_assessment_per_kind
    fan_out([assessment], [event("issued", 1)])
    fan_out([assessment(status: "retracted")], [event("retracted", 2, at: NOW + 1)], now: NOW + 1)

    keys = @outbox.requests.map(&:idempotency_key)
    assert_equal 2, keys.uniq.length
    assert(keys.all? { |key| key.match?(/\A[0-9a-f]{64}\z/) })
  end

  private

  def fan_out(assessments, events, now: NOW, only: nil)
    workspaces = only || @bound
    use_case = PrismHub::UseCases::FanOutSignalEvents.new(
      subscription_repository: @subscriptions,
      ledger: @ledger,
      binding_repository: Bindings.new(@bound & workspaces),
      outbox_repository: @outbox,
      logger: Logger.new(File::NULL),
      max_age_seconds: 1800,
      cooldown_seconds: 300
    )
    use_case.call(assessments: assessments, events: events, now: now)
  end

  def subscription(workspace, cell, categories: %w[drone bomb missile], include_nearby: true)
    PrismHub::Domain::AlertSubscription.new(
      workspace_id: workspace,
      cell: cell,
      categories: categories,
      include_nearby: include_nearby,
      updated_at: NOW
    )
  end

  def assessment(id: ID, place: "Київ", hazard: "drone", status: "active", proximity: "target", cells: [KYIV], valid_until: NOW + 1800)
    {
      "assessment_id" => id,
      "class" => hazard,
      "kinds" => ["air.#{hazard == "drone" ? "attack_drone" : hazard}"],
      "place" => {"id" => "geonames:1", "name" => place},
      "proximity" => proximity,
      "cells" => {"resolution" => 6, "cells" => cells},
      "valid_from" => (NOW - 60).iso8601,
      "valid_until" => valid_until.iso8601,
      "status" => status,
      "likelihood" => "moderate",
      "evidence" => [
        {
          "source_id" => "telegram.channel:vanek_nikolaev",
          "evidence_id" => "vanek_nikolaev/100",
          "url" => "https://t.me/vanek_nikolaev/100",
          "observed_at" => (NOW - 60).iso8601
        }
      ]
    }
  end

  def event(kind, seq, id: ID, at: NOW - 60)
    evidence = {"source_id" => "telegram.channel:vanek_nikolaev", "evidence_id" => "vanek_nikolaev/101", "url" => "https://t.me/vanek_nikolaev/101"}
    {"assessment_id" => id, "seq" => seq, "kind" => kind, "effective_at" => at.iso8601, "evidence" => evidence}
  end
end
