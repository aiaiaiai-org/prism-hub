# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class SocialAccountAccessTest < Minitest::Test
  def setup
    @identity = PrismHub::Domain::UserIdentity.new(
      id: "identity-1",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
      status: "active"
    )
    @account = PrismHub::Domain::SocialAccount.new(
      id: "account-1",
      provider: "instagram",
      provider_account_id: "17841400000000000"
    )
  end

  def test_active_roles_can_publish
    %w[owner manager publisher].each do |role|
      access = PrismHub::Domain::SocialAccountAccess.new(
        id: "access-#{role}",
        user_identity: @identity,
        social_account: @account,
        role: role,
        status: "active"
      )

      assert access.can_publish?
    end
  end

  def test_revoked_access_cannot_publish_and_requires_revoked_at
    revoked_at = Time.utc(2026, 8, 28, 4, 45, 0)
    access = PrismHub::Domain::SocialAccountAccess.new(
      id: "access-1",
      user_identity: @identity,
      social_account: @account,
      role: "publisher",
      status: "revoked",
      revoked_at: revoked_at
    )

    refute access.can_publish?
    assert_equal revoked_at, access.revoked_at

    assert_raises(PrismHub::InputError) do
      PrismHub::Domain::SocialAccountAccess.new(
        id: "access-2",
        user_identity: @identity,
        social_account: @account,
        role: "publisher",
        status: "revoked"
      )
    end
  end
end
