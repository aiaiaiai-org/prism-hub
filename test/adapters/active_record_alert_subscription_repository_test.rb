# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordAlertSubscriptionRepositoryTest < Minitest::Test
  CELL = "860335a97ffffff".freeze
  OTHER_CELL = "8601aa26fffffff".freeze

  def setup
    clear_tables
    @identity_repository = PrismHub::Adapters::ActiveRecordUserIdentityRepository.new
    @membership_repository = PrismHub::Adapters::ActiveRecordWorkspaceMembershipRepository.new
    @repository = PrismHub::Adapters::ActiveRecordAlertSubscriptionRepository.new
    @workspace = create_workspace("personal-a")
    @owner = provision_identity("0xuser-a")
    @membership_repository.grant(user_identity: @owner, workspace_id: @workspace.identifier, role: "owner")
  end

  def teardown
    clear_tables
  end

  def test_find_is_nil_before_anything_is_saved
    assert_nil @repository.find(workspace_id: @workspace.identifier)
  end

  def test_save_stores_the_choice_and_find_returns_it
    saved = save(Time.utc(2026, 9, 30, 9, 0))

    assert_equal CELL, saved.cell
    assert_equal %w[drone missile], saved.categories
    assert_equal false, saved.include_nearby
    assert_equal Time.utc(2026, 9, 30, 9, 0), saved.updated_at
    assert_equal saved.to_h, @repository.find(workspace_id: @workspace.identifier).to_h
  end

  def test_saving_again_replaces_the_subscription_instead_of_adding_one
    save(Time.utc(2026, 9, 30, 9, 0))
    replaced = save(
      Time.utc(2026, 9, 30, 9, 5),
      cell: OTHER_CELL,
      categories: %w[bomb],
      include_nearby: true
    )

    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::AlertSubscription.count
    assert_equal OTHER_CELL, replaced.cell
    assert_equal %w[bomb], replaced.categories
    assert_equal Time.utc(2026, 9, 30, 9, 5), replaced.updated_at
    assert_equal OTHER_CELL, @repository.find(workspace_id: @workspace.identifier).cell
  end

  def test_each_workspace_has_its_own_subscription
    other = create_workspace("personal-b")
    other_owner = provision_identity("0xuser-b")
    @membership_repository.grant(user_identity: other_owner, workspace_id: other.identifier, role: "owner")

    save(Time.utc(2026, 9, 30, 9, 0))
    @repository.save(
      workspace_id: other.identifier,
      actor_user_identity_id: other_owner.id,
      cell: OTHER_CELL,
      categories: %w[bomb],
      include_nearby: true,
      occurred_at: Time.utc(2026, 9, 30, 9, 1)
    )

    assert_equal CELL, @repository.find(workspace_id: @workspace.identifier).cell
    assert_equal OTHER_CELL, @repository.find(workspace_id: other.identifier).cell
  end

  def test_only_the_active_owner_may_save
    member = provision_identity("0xuser-member")
    @membership_repository.grant(user_identity: member, workspace_id: @workspace.identifier, role: "member")
    stranger = provision_identity("0xuser-stranger")

    [member, stranger].each do |actor|
      error = assert_raises(PrismHub::AlertSubscriptionConflictError) do
        save(Time.utc(2026, 9, 30, 9, 0), actor: actor)
      end
      assert_equal "hub.alert_subscription.owner_required", error.code
    end
    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::AlertSubscription.count
  end

  def test_a_disabled_workspace_cannot_be_subscribed
    @workspace.update!(status: "disabled")

    error = assert_raises(PrismHub::AlertSubscriptionConflictError) { save(Time.utc(2026, 9, 30, 9, 0)) }
    assert_equal "hub.alert_subscription.workspace_unavailable", error.code
  end

  def test_clear_deletes_the_row_and_leaves_nothing_behind
    save(Time.utc(2026, 9, 30, 9, 0))

    assert_nil @repository.clear(
      workspace_id: @workspace.identifier,
      actor_user_identity_id: @owner.id,
      occurred_at: Time.utc(2026, 9, 30, 9, 10)
    )

    assert_nil @repository.find(workspace_id: @workspace.identifier)
    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::AlertSubscription.count
  end

  def test_clear_is_idempotent_and_still_checks_the_owner
    2.times do
      @repository.clear(
        workspace_id: @workspace.identifier,
        actor_user_identity_id: @owner.id,
        occurred_at: Time.utc(2026, 9, 30, 9, 10)
      )
    end
    stranger = provision_identity("0xuser-stranger")

    error = assert_raises(PrismHub::AlertSubscriptionConflictError) do
      @repository.clear(
        workspace_id: @workspace.identifier,
        actor_user_identity_id: stranger.id,
        occurred_at: Time.utc(2026, 9, 30, 9, 10)
      )
    end
    assert_equal "hub.alert_subscription.owner_required", error.code
  end

  def test_a_revoked_owner_can_no_longer_change_it
    save(Time.utc(2026, 9, 30, 9, 0))
    # Revoked behind the repository's back, as a concurrent revocation would be: the owner is
    # rechecked inside each change.
    PrismHub::Adapters::ActiveRecordRecords::WorkspaceMembership.update_all(status: "revoked", revoked_at: Time.utc(2026, 9, 30, 9, 1))

    assert_raises(PrismHub::AlertSubscriptionConflictError) { save(Time.utc(2026, 9, 30, 9, 2), cell: OTHER_CELL) }
    assert_equal CELL, @repository.find(workspace_id: @workspace.identifier).cell
  end

  def test_the_table_holds_no_coordinates_and_no_names
    columns = ActiveRecord::Base.connection.columns("alert_subscriptions").map(&:name)

    assert_equal %w[id workspace_id cell categories include_nearby created_at updated_at].sort, columns.sort
    columns.each { |name| refute_match(/lat|lon|coord|name|position/, name) }
  end

  def test_a_workspace_that_still_has_a_subscription_cannot_be_deleted_by_accident
    save(Time.utc(2026, 9, 30, 9, 0))

    assert_raises(ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError) { @workspace.destroy! }
  end

  private

  def save(time, actor: @owner, cell: CELL, categories: %w[missile drone], include_nearby: false)
    @repository.save(
      workspace_id: @workspace.identifier,
      actor_user_identity_id: actor.id,
      cell: cell,
      categories: categories.sort,
      include_nearby: include_nearby,
      occurred_at: time
    )
  end

  def create_workspace(identifier)
    PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(identifier: identifier, status: "active")
  end

  def provision_identity(canonical_id)
    @identity_repository.provision(
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: canonical_id)
    )
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
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
