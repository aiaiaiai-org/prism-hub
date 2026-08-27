# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ProviderIdentityBindingTest < Minitest::Test
  def test_active_binding_cannot_carry_a_revocation_timestamp
    error = assert_raises(PrismHub::InputError) do
      binding(status: "active", revoked_at: Time.utc(2026, 8, 27, 13, 0, 0))
    end

    assert_equal "hub.provider_identity_binding.state.invalid", error.code
  end

  def test_revoked_binding_requires_a_revocation_timestamp
    error = assert_raises(PrismHub::InputError) do
      binding(status: "revoked", revoked_at: nil)
    end

    assert_equal "hub.provider_identity_binding.state.invalid", error.code
  end

  private

  def binding(status:, revoked_at:)
    PrismHub::Domain::ProviderIdentityBinding.new(
      id: "binding-1",
      user_identity: PrismHub::Domain::UserIdentity.new(
        id: "identity-1",
        canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
        status: "active"
      ),
      provider_subject: PrismHub::Domain::ProviderSubject.new(
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      ),
      status: status,
      revoked_at: revoked_at
    )
  end
end
