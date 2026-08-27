# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class WorkspaceMembershipTest < Minitest::Test
  def test_active_owner_membership
    membership = build_membership(role: "owner", status: "active")

    assert membership.active?
    assert membership.owner?
    assert_nil membership.revoked_at
  end

  def test_rejects_unknown_role
    error = assert_raises(PrismHub::InputError) do
      build_membership(role: "publisher", status: "active")
    end

    assert_equal "hub.workspace_membership.role.invalid", error.code
  end

  def test_rejects_incoherent_revoked_state
    error = assert_raises(PrismHub::InputError) do
      build_membership(role: "member", status: "revoked")
    end

    assert_equal "hub.workspace_membership.state.invalid", error.code
  end

  def test_accepts_revoked_membership_with_timestamp
    timestamp = Time.utc(2026, 8, 27, 15, 45)
    membership = build_membership(role: "member", status: "revoked", revoked_at: timestamp)

    refute membership.active?
    assert_equal timestamp, membership.revoked_at
  end

  private

  def build_membership(role:, status:, revoked_at: nil)
    PrismHub::Domain::WorkspaceMembership.new(
      id: "membership-1",
      workspace_id: "personal",
      user_identity: PrismHub::Domain::UserIdentity.new(
        id: "identity-1",
        canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
        status: "active"
      ),
      role: role,
      status: status,
      revoked_at: revoked_at
    )
  end
end
