# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class AlertSubscriptionsMigrationTest < Minitest::Test
  CELL = "860335a97ffffff".freeze

  def setup
    clear_tables
    @workspace = PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(
      identifier: "migration-workspace",
      status: "active"
    )
  end

  def teardown
    clear_tables
  end

  def test_database_accepts_a_valid_subscription
    record = create(cell: CELL, categories: %w[drone bomb missile])

    assert record.persisted?
    assert_equal true, record.include_nearby, "nearby warnings default to on"
  end

  def test_database_rejects_anything_that_is_not_a_resolution_six_cell
    [
      "50.4501,30.5234",
      "8a0335a97ffffff",
      "860335A97FFFFFF",
      "860335a97fffff",
      ""
    ].each do |cell|
      assert_rejected("cell #{cell.inspect}") { create(cell: cell, categories: %w[drone]) }
    end
  end

  def test_database_rejects_empty_unknown_or_oversized_category_lists
    [[], %w[shahed], %w[drone shahed], %w[drone bomb missile drone]].each do |categories|
      assert_rejected("categories #{categories.inspect}") { create(cell: CELL, categories: categories) }
    end
  end

  def test_database_allows_one_subscription_per_workspace
    create(cell: CELL, categories: %w[drone])

    assert_rejected("a second subscription") { create(cell: CELL, categories: %w[bomb]) }
  end

  def test_the_migration_is_reversible
    connection = ActiveRecord::Base.connection
    assert connection.table_exists?(:alert_subscriptions)
    assert_includes connection.indexes(:alert_subscriptions).map(&:name), "idx_alert_subscriptions_cell"
    assert_includes connection.indexes(:alert_subscriptions).map(&:name), "idx_alert_subscriptions_workspace"
    names = connection.check_constraints(:alert_subscriptions).map(&:name)
    assert_equal %w[alert_subscriptions_categories_check alert_subscriptions_cell_check], names.sort
  end

  private

  def create(cell:, categories:)
    PrismHub::Adapters::ActiveRecordRecords::AlertSubscription.create!(
      workspace: @workspace,
      cell: cell,
      categories: categories
    )
  end

  def assert_rejected(what)
    assert_raises(ActiveRecord::StatementInvalid, "#{what} should be refused by the database") do
      ActiveRecord::Base.transaction(requires_new: true) { yield }
    end
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[alert_subscriptions workspaces].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
