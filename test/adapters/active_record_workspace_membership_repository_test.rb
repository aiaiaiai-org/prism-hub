# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordWorkspaceMembershipRepositoryTest < Minitest::Test
  def setup
    clear_tables
    @identity_repository = PrismHub::Adapters::ActiveRecordUserIdentityRepository.new
    @repository = PrismHub::Adapters::ActiveRecordWorkspaceMembershipRepository.new
    @workspace = PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(
      identifier: "personal",
      status: "active"
    )
    @identity = @identity_repository.provision(
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky")
    )
  end

  def teardown
    clear_tables
  end

  def test_grant_is_idempotent_for_same_role
    first = @repository.grant(user_identity: @identity, workspace_id: "personal", role: "owner")
    second = @repository.grant(user_identity: @identity, workspace_id: "personal", role: "owner")

    assert_equal first.id, second.id
    assert_equal "owner", second.role
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::WorkspaceMembership.count
  end

  def test_grant_rejects_silent_role_change
    @repository.grant(user_identity: @identity, workspace_id: "personal", role: "member")

    error = assert_raises(PrismHub::WorkspaceMembershipConflictError) do
      @repository.grant(user_identity: @identity, workspace_id: "personal", role: "admin")
    end

    assert_equal "hub.workspace_membership.role_mismatch", error.code
  end

  def test_revoked_membership_cannot_be_granted_again
    second_identity = provision_identity("second")
    @repository.grant(user_identity: second_identity, workspace_id: "personal", role: "member")
    @repository.revoke(
      user_identity_id: second_identity.id,
      workspace_id: "personal",
      revoked_at: Time.utc(2026, 8, 27, 15, 50)
    )

    error = assert_raises(PrismHub::WorkspaceMembershipConflictError) do
      @repository.grant(user_identity: second_identity, workspace_id: "personal", role: "member")
    end

    assert_equal "hub.workspace_membership.revoked", error.code
  end

  def test_revoke_is_idempotent_and_preserves_first_timestamp
    second_identity = provision_identity("second")
    @repository.grant(user_identity: second_identity, workspace_id: "personal", role: "member")
    first_time = Time.utc(2026, 8, 27, 15, 51)
    second_time = Time.utc(2026, 8, 27, 16, 0)

    first = @repository.revoke(
      user_identity_id: second_identity.id,
      workspace_id: "personal",
      revoked_at: first_time
    )
    second = @repository.revoke(
      user_identity_id: second_identity.id,
      workspace_id: "personal",
      revoked_at: second_time
    )

    assert_equal first_time, first.revoked_at
    assert_equal first_time, second.revoked_at
  end

  def test_last_active_owner_cannot_be_revoked
    @repository.grant(user_identity: @identity, workspace_id: "personal", role: "owner")

    error = assert_raises(PrismHub::WorkspaceMembershipConflictError) do
      @repository.revoke(
        user_identity_id: @identity.id,
        workspace_id: "personal",
        revoked_at: Time.utc(2026, 8, 27, 15, 52)
      )
    end

    assert_equal "hub.workspace_membership.last_owner", error.code
  end

  def test_owner_can_be_revoked_when_another_active_owner_exists
    second_identity = provision_identity("second-owner")
    @repository.grant(user_identity: @identity, workspace_id: "personal", role: "owner")
    @repository.grant(user_identity: second_identity, workspace_id: "personal", role: "owner")

    membership = @repository.revoke(
      user_identity_id: @identity.id,
      workspace_id: "personal",
      revoked_at: Time.utc(2026, 8, 27, 15, 53)
    )

    assert_equal "revoked", membership.status
  end

  def test_disabled_identity_cannot_receive_membership
    PrismHub::Adapters::ActiveRecordRecords::UserIdentity.find(@identity.id).update!(status: "disabled")

    error = assert_raises(PrismHub::UserIdentityConflictError) do
      @repository.grant(user_identity: @identity, workspace_id: "personal", role: "member")
    end

    assert_equal "hub.user_identity.disabled", error.code
  end

  def test_find_returns_historical_revoked_membership
    second_identity = provision_identity("second")
    @repository.grant(user_identity: second_identity, workspace_id: "personal", role: "member")
    @repository.revoke(
      user_identity_id: second_identity.id,
      workspace_id: "personal",
      revoked_at: Time.utc(2026, 8, 27, 15, 54)
    )

    membership = @repository.find(user_identity_id: second_identity.id, workspace_id: "personal")

    assert_equal "revoked", membership.status
  end

  private

  def provision_identity(canonical_id)
    @identity_repository.provision(
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: canonical_id)
    )
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
      workspace_memberships
      provider_identity_bindings
      client_credentials
      capability_grants
      channel_grants
      service_principals
      user_identities
      workspaces
    ].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
