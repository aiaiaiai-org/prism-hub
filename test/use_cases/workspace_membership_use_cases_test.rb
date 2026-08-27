# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class WorkspaceMembershipUseCasesTest < Minitest::Test
  class UserIdentityRepository
    def initialize(identity)
      @identity = identity
    end

    def find(id:)
      @identity if @identity.id == id
    end
  end

  class MembershipRepository
    attr_reader :granted, :revoked

    def initialize(membership)
      @membership = membership
    end

    def grant(user_identity:, workspace_id:, role:)
      @granted = [user_identity, workspace_id, role]
      @membership
    end

    def find(user_identity_id:, workspace_id:)
      return unless @membership.user_identity.id == user_identity_id
      return unless @membership.workspace_id == workspace_id

      @membership
    end

    def revoke(user_identity_id:, workspace_id:, revoked_at:)
      @revoked = [user_identity_id, workspace_id, revoked_at]
      @membership
    end
  end

  def test_grant_resolves_user_identity_before_persisting_relation
    membership = build_membership
    membership_repository = MembershipRepository.new(membership)
    use_case = PrismHub::UseCases::GrantWorkspaceMembership.new(
      user_identity_repository: UserIdentityRepository.new(membership.user_identity),
      workspace_membership_repository: membership_repository
    )

    result = use_case.call(
      user_identity_id: membership.user_identity.id,
      workspace_id: "personal",
      role: "owner"
    )

    assert_same membership, result
    assert_equal [membership.user_identity, "personal", "owner"], membership_repository.granted
  end

  def test_resolve_returns_only_active_membership_for_active_identity
    membership = build_membership
    use_case = PrismHub::UseCases::ResolveWorkspaceMembership.new(
      workspace_membership_repository: MembershipRepository.new(membership)
    )

    assert_same membership, use_case.call(user_identity_id: membership.user_identity.id, workspace_id: "personal")
  end

  def test_resolve_hides_revoked_membership
    membership = build_membership(status: "revoked", revoked_at: Time.utc(2026, 8, 27, 16, 5))
    use_case = PrismHub::UseCases::ResolveWorkspaceMembership.new(
      workspace_membership_repository: MembershipRepository.new(membership)
    )

    assert_nil use_case.call(user_identity_id: membership.user_identity.id, workspace_id: "personal")
  end

  def test_revoke_uses_injected_clock
    membership = build_membership(role: "member")
    repository = MembershipRepository.new(membership)
    now = Time.utc(2026, 8, 27, 16, 6)
    clock = Struct.new(:value) do
      def now
        value
      end
    end.new(now)
    use_case = PrismHub::UseCases::RevokeWorkspaceMembership.new(
      workspace_membership_repository: repository,
      clock: clock
    )

    use_case.call(user_identity_id: membership.user_identity.id, workspace_id: "personal")

    assert_equal [membership.user_identity.id, "personal", now], repository.revoked
  end

  private

  def build_membership(role: "owner", status: "active", revoked_at: nil)
    identity = PrismHub::Domain::UserIdentity.new(
      id: "identity-1",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
      status: "active"
    )
    PrismHub::Domain::WorkspaceMembership.new(
      id: "membership-1",
      workspace_id: "personal",
      user_identity: identity,
      role: role,
      status: status,
      revoked_at: revoked_at
    )
  end
end
