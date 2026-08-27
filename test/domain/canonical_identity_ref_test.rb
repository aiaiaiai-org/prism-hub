# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class CanonicalIdentityRefTest < Minitest::Test
  def test_preserves_provider_independent_identity
    identity = PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky")

    assert_equal "person", identity.type
    assert_equal "0x0sky", identity.id
    assert_equal "person:0x0sky", identity.to_s
  end

  def test_accepts_all_mind_identity_types_without_making_them_users
    PrismHub::Domain::CanonicalIdentityRef::TYPES.each do |type|
      identity = PrismHub::Domain::CanonicalIdentityRef.new(type: type, id: "subject")
      assert_equal type, identity.type
    end
  end
end
