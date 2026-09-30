# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class AlertSubscriptionTest < Minitest::Test
  CELL = "860335a97ffffff".freeze

  def build(**overrides)
    PrismHub::Domain::AlertSubscription.new(
      **{
        workspace_id: "personal-user",
        cell: CELL,
        categories: %w[missile drone],
        include_nearby: true,
        updated_at: Time.utc(2026, 9, 30, 9, 0)
      }.merge(overrides)
    )
  end

  def test_holds_a_cell_categories_and_the_nearby_flag_and_is_frozen
    subscription = build

    assert_equal CELL, subscription.cell
    assert_equal %w[drone missile], subscription.categories, "categories are kept sorted"
    assert subscription.include_nearby
    assert subscription.frozen?
    assert subscription.categories.frozen?
    assert subscription.cell.frozen?
  end

  def test_public_shape_is_exactly_what_the_person_chose
    assert_equal(
      {"cell" => CELL, "categories" => %w[drone missile], "include_nearby" => true},
      build.to_h
    )
    refute_includes build.to_h.keys, "workspace_id"
  end

  def test_only_resolution_six_cells_are_accepted
    [
      "860335a97ffffff".upcase,     # not lowercase
      "8a0335a97ffffff",            # a finer cell
      "820335a97ffffff",            # a coarser cell
      "860335a97fffff",             # too short
      "860335a97ffffffa",           # too long
      "not-a-cell",
      "",
      nil,
      86_033_5
    ].each do |cell|
      error = assert_raises(PrismHub::InputError, "#{cell.inspect} should be refused") { build(cell: cell) }
      assert_equal "hub.alert_subscription.cell.invalid", error.code
    end
  end

  def test_coordinates_can_never_be_mistaken_for_a_cell
    error = assert_raises(PrismHub::InputError) { build(cell: "50.4501,30.5234") }
    assert_equal "hub.alert_subscription.cell.invalid", error.code
  end

  def test_categories_must_be_a_non_empty_list_of_distinct_known_values
    [[], %w[drone drone], %w[shahed], %w[drone bomb missile extra], "drone", nil, [:drone]].each do |categories|
      error = assert_raises(PrismHub::InputError, "#{categories.inspect} should be refused") do
        build(categories: categories)
      end
      assert_equal "hub.alert_subscription.categories.invalid", error.code
    end
    assert_equal %w[bomb drone missile], build(categories: %w[missile bomb drone]).categories
  end

  def test_the_nearby_flag_must_be_a_boolean
    ["true", 1, nil].each do |value|
      error = assert_raises(PrismHub::InputError) { build(include_nearby: value) }
      assert_equal "hub.alert_subscription.include_nearby.invalid", error.code
    end
    refute build(include_nearby: false).include_nearby
  end

  def test_workspace_and_time_are_validated
    assert_equal "hub.alert_subscription.workspace_id.invalid",
      assert_raises(PrismHub::InputError) { build(workspace_id: "") }.code
    assert_equal "hub.alert_subscription.updated_at.invalid",
      assert_raises(PrismHub::InputError) { build(updated_at: "yesterday") }.code
  end

  def test_the_domain_vocabulary_matches_the_client_categories
    assert_equal %w[drone bomb missile], PrismHub::Domain::AlertSubscription::CATEGORIES
  end
end
