# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class SocialAccountAccessTest < Minitest::Test
  def setup
    @identity = identity("active")
    @account = PrismHub::Domain::SocialAccount.new(
      id: "account-1", provider: "instagram", provider_account_id: "17841400000000000"
    )
  end

  def test_permission_requires_active_access_and_active_person_for_every_role
    %w[owner manager publisher].each do |role|
      assert build(role: role).can_publish?
      refute build(role: role, user_identity: identity("disabled")).can_publish?
      refute build(role: role, status: "revoked", revoked_at: Time.utc(2026, 8, 28)).can_publish?
    end
  end

  def test_owner_describes_role_not_permission
    access = build(role: "owner", status: "revoked", revoked_at: Time.utc(2026, 8, 28))

    assert access.owner?
    refute access.active?
    refute access.can_publish?
  end

  def test_rejects_invalid_state_and_references_with_stable_errors
    [
      [{id: ""}, "id"],
      [{user_identity: nil}, "user_identity"],
      [{social_account: nil}, "social_account"],
      [{role: "admin"}, "role"],
      [{status: "disabled"}, "status"],
      [{revoked_at: "2026-08-28"}, "revoked_at"],
      [{revoked_at: Time.utc(2026, 8, 28)}, "state"],
      [{status: "revoked"}, "state"]
    ].each do |attributes, field|
      error = assert_raises(PrismHub::InputError) { build(**attributes) }
      assert_equal "hub.social_account_access.#{field}.invalid", error.code
    end
  end

  def test_timestamp_is_an_owned_utc_copy
    time = Time.new(2026, 8, 28, 12, 0, 0, "+03:00")
    access = build(status: "revoked", revoked_at: time)

    assert_equal time, access.revoked_at
    assert access.revoked_at.utc?
    assert access.revoked_at.frozen?
    refute time.frozen?
    assert_equal 10800, time.utc_offset
    refute_same time, access.revoked_at
  end

  def test_strings_are_owned_immutable_copies
    role = +"owner"
    status = +"active"
    id = +"access-1"
    access = build(id: id, role: role, status: status)

    [id, role, status].each { |value| value << "changed" }
    assert_equal "owner", access.role
    assert_equal "active", access.status
    assert_equal "access-1", access.id
    assert access.frozen?
  end

  private

  def identity(status)
    PrismHub::Domain::UserIdentity.new(
      id: "identity-1",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
      status: status
    )
  end

  def build(**attributes)
    PrismHub::Domain::SocialAccountAccess.new(
      **{id: "access-1", user_identity: @identity, social_account: @account, role: "publisher", status: "active"}.merge(attributes)
    )
  end
end
