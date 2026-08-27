# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ProvisionUserIdentityTest < Minitest::Test
  class Repository < PrismHub::Ports::UserIdentityRepository
    attr_reader :canonical_identity

    def provision(canonical_identity:)
      @canonical_identity = canonical_identity
      :provisioned
    end
  end

  def test_only_person_identity_can_become_a_user_identity
    repository = Repository.new
    use_case = PrismHub::UseCases::ProvisionUserIdentity.new(user_identity_repository: repository)

    error = assert_raises(PrismHub::InputError) do
      use_case.call(canonical_type: "organization", canonical_id: "aiaiaiai")
    end

    assert_equal "hub.user_identity.subject.invalid", error.code
    assert_nil repository.canonical_identity
  end
end
