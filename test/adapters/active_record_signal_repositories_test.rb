# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordSignalRepositoriesTest < Minitest::Test
  CELL = "861e68697ffffff".freeze
  OTHER = "8601aa26fffffff".freeze
  T0 = Time.utc(2026, 9, 30, 12, 0, 0)
  SOURCE = "telegram.channel:vanek_nikolaev".freeze

  def setup
    clear_tables
    @identities = PrismHub::Adapters::ActiveRecordUserIdentityRepository.new
    @memberships = PrismHub::Adapters::ActiveRecordWorkspaceMembershipRepository.new
    @subscriptions = PrismHub::Adapters::ActiveRecordAlertSubscriptionRepository.new
    @window = PrismHub::Adapters::ActiveRecordSignalWindowRepository.new
    @ledger = PrismHub::Adapters::ActiveRecordSignalAlertLedger.new
    @a = person("personal-a", "0xuser-a", CELL, %w[drone missile])
    @b = person("personal-b", "0xuser-b", OTHER, %w[drone])
  end

  def teardown
    clear_tables
  end

  def test_covering_finds_subscribers_in_the_cells_who_asked_for_the_class
    found = @subscriptions.covering(cells: [CELL, "861e6869fffffff"], category: "drone")

    assert_equal ["personal-a"], found.map(&:workspace_id)
    assert_empty @subscriptions.covering(cells: [CELL], category: "bomb")
    assert_empty @subscriptions.covering(cells: [], category: "drone")
    assert_equal %w[personal-a personal-b], @subscriptions.covering(cells: [CELL, OTHER], category: "drone").map(&:workspace_id).sort
  end

  def test_find_all_returns_the_subscriptions_that_still_exist
    found = @subscriptions.find_all(workspace_ids: %w[personal-a personal-gone])

    assert_equal ["personal-a"], found.map(&:workspace_id)
    assert_empty @subscriptions.find_all(workspace_ids: [])
  end

  def test_the_cursor_moves_forward_and_is_kept_per_source
    assert_nil @window.cursor(source_id: SOURCE)

    @window.advance_cursor(source_id: SOURCE, cursor: "100", at: T0)
    @window.advance_cursor(source_id: SOURCE, cursor: "105", at: T0 + 60)
    @window.advance_cursor(source_id: "telegram.channel:other", cursor: "7", at: T0)

    assert_equal "105", @window.cursor(source_id: SOURCE)
    assert_equal "7", @window.cursor(source_id: "telegram.channel:other")
    assert_equal 2, PrismHub::Adapters::ActiveRecordRecords::SignalSourceCursor.count
  end

  def test_evidence_is_stored_once_and_an_edit_replaces_it
    @window.store(evidence: [item(1, T0, "шахеди на Київ")])
    @window.store(evidence: [item(1, T0, "мінус шахеди на Київ"), item(2, T0 + 60, "інше")])

    window = @window.since(time: T0 - 1, limit: 10)

    assert_equal 2, window.length
    assert_equal "мінус шахеди на Київ", window.first.fetch("text")
  end

  def test_the_window_is_oldest_first_bounded_and_limited_to_the_newest
    (1..5).each { |n| @window.store(evidence: [item(n, T0 + n * 60, "x#{n}")]) }

    assert_equal %w[x1 x2 x3 x4 x5], @window.since(time: T0, limit: 10).map { |i| i["text"] }
    assert_equal %w[x4 x5], @window.since(time: T0, limit: 2).map { |i| i["text"] }
    assert_equal %w[x3 x4 x5], @window.since(time: T0 + 3 * 60, limit: 10).map { |i| i["text"] }
  end

  def test_prune_drops_only_what_left_the_window
    (1..3).each { |n| @window.store(evidence: [item(n, T0 + n * 60, "x#{n}")]) }

    @window.prune(before: T0 + 2 * 60)

    assert_equal %w[x2 x3], @window.since(time: T0, limit: 10).map { |i| i["text"] }
  end

  def test_the_ledger_records_once_per_assessment_person_and_kind
    assert @ledger.record(**entry("a1", "personal-a", "alert"))
    refute @ledger.record(**entry("a1", "personal-a", "alert"))
    assert @ledger.record(**entry("a1", "personal-a", "retraction"))

    assert @ledger.recorded?(assessment_id: "a1", workspace_id: "personal-a", kind: "alert")
    refute @ledger.recorded?(assessment_id: "a1", workspace_id: "personal-b", kind: "alert")
    assert_equal 2, PrismHub::Adapters::ActiveRecordRecords::SignalAlertDelivery.count
  end

  def test_recent_alert_looks_at_the_person_the_class_and_the_time
    @ledger.record(**entry("a1", "personal-a", "alert", at: T0))

    assert @ledger.recent_alert?(workspace_id: "personal-a", hazard_class: "drone", since: T0 - 1)
    refute @ledger.recent_alert?(workspace_id: "personal-a", hazard_class: "drone", since: T0 + 1)
    refute @ledger.recent_alert?(workspace_id: "personal-a", hazard_class: "missile", since: T0 - 1)
    refute @ledger.recent_alert?(workspace_id: "personal-b", hazard_class: "drone", since: T0 - 1)
  end

  def test_a_retraction_does_not_count_as_a_recent_alert
    @ledger.record(**entry("a1", "personal-a", "retraction", at: T0))

    refute @ledger.recent_alert?(workspace_id: "personal-a", hazard_class: "drone", since: T0 - 1)
  end

  def test_alerted_workspaces_lists_only_those_told_the_alert
    @ledger.record(**entry("a1", "personal-a", "alert"))
    @ledger.record(**entry("a1", "personal-b", "retraction"))
    @ledger.record(**entry("a2", "personal-b", "alert"))

    assert_equal ["personal-a"], @ledger.alerted_workspaces(assessment_id: "a1")
  end

  def test_prune_removes_old_entries
    @ledger.record(**entry("a1", "personal-a", "alert", at: T0))
    @ledger.record(**entry("a2", "personal-a", "alert", at: T0 + 3600))

    @ledger.prune(before: T0 + 60)

    refute @ledger.recorded?(assessment_id: "a1", workspace_id: "personal-a", kind: "alert")
    assert @ledger.recorded?(assessment_id: "a2", workspace_id: "personal-a", kind: "alert")
  end

  def test_clearing_a_subscription_forgets_what_the_person_was_told
    @ledger.record(**entry("a1", "personal-a", "alert"))
    @ledger.record(**entry("a1", "personal-b", "alert"))

    @subscriptions.clear(workspace_id: "personal-a", actor_user_identity_id: @a.id, occurred_at: T0)

    refute @ledger.recorded?(assessment_id: "a1", workspace_id: "personal-a", kind: "alert")
    assert @ledger.recorded?(assessment_id: "a1", workspace_id: "personal-b", kind: "alert")
  end

  private

  def person(workspace, canonical, cell, categories)
    PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(identifier: workspace, status: "active")
    identity = @identities.provision(canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: canonical))
    @memberships.grant(user_identity: identity, workspace_id: workspace, role: "owner")
    @subscriptions.save(
      workspace_id: workspace,
      actor_user_identity_id: identity.id,
      cell: cell,
      categories: categories,
      include_nearby: true,
      occurred_at: T0
    )
    identity
  end

  def item(number, published_at, text)
    {
      "source_id" => SOURCE,
      "external_id" => "vanek_nikolaev/#{number}",
      "published_at" => published_at.iso8601,
      "text" => text
    }
  end

  def entry(assessment, workspace, kind, at: T0)
    {assessment_id: assessment, workspace_id: workspace, hazard_class: "drone", kind: kind, event_seq: 1, at: at}
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
      signal_alert_deliveries
      signal_evidence
      signal_source_cursors
      alert_subscriptions
      workspace_memberships
      provider_identity_bindings
      user_identities
      workspaces
    ].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
