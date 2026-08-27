# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ProviderIdentityUseCasesTest < Minitest::Test
  class InMemoryIdentityRepository
    def initialize(identity)
      @identity = identity
    end

    def find(id:)
      @identity if @identity.id == id
    end
  end

  class InMemoryBindingRepository
    attr_reader :binding

    def bind(user_identity:, provider_subject:)
      @binding = PrismHub::Domain::ProviderIdentityBinding.new(
        id: "binding-1",
        user_identity: user_identity,
        provider_subject: provider_subject,
        status: "active"
      )
    end

    def find(provider_subject:)
      binding if binding&.provider_subject == provider_subject
    end

    def revoke(provider_subject:, revoked_at:)
      current = find(provider_subject: provider_subject)
      @binding = PrismHub::Domain::ProviderIdentityBinding.new(
        id: current.id,
        user_identity: current.user_identity,
        provider_subject: current.provider_subject,
        status: "revoked",
        revoked_at: revoked_at
      )
    end
  end

  def setup
    @identity = PrismHub::Domain::UserIdentity.new(
      id: "identity-1",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
      status: "active"
    )
    @identity_repository = InMemoryIdentityRepository.new(@identity)
    @binding_repository = InMemoryBindingRepository.new
  end

  def test_bind_resolves_internal_user_identity_before_persisting_provider_subject
    binding = PrismHub::UseCases::BindProviderIdentity.new(
      user_identity_repository: @identity_repository,
      binding_repository: @binding_repository
    ).call(
      user_identity_id: @identity.id,
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )

    assert_equal @identity, binding.user_identity
    assert_equal "telegram", binding.provider_subject.provider
  end

  def test_bind_fails_when_user_identity_does_not_exist
    error = assert_raises(PrismHub::UserIdentityNotFoundError) do
      PrismHub::UseCases::BindProviderIdentity.new(
        user_identity_repository: @identity_repository,
        binding_repository: @binding_repository
      ).call(
        user_identity_id: "missing",
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      )
    end

    assert_equal "hub.user_identity.not_found", error.code
  end

  def test_resolve_returns_only_active_binding
    bind
    resolver = PrismHub::UseCases::ResolveProviderIdentity.new(binding_repository: @binding_repository)

    assert_equal @binding_repository.binding, resolve(resolver)

    PrismHub::UseCases::RevokeProviderIdentity.new(
      binding_repository: @binding_repository,
      clock: -> { Time.utc(2026, 8, 27, 13, 45, 0) }
    ).call(provider: "telegram", provider_scope: "global", subject_id: "123456789")

    assert_nil resolve(resolver)
  end

  private

  def bind
    PrismHub::UseCases::BindProviderIdentity.new(
      user_identity_repository: @identity_repository,
      binding_repository: @binding_repository
    ).call(
      user_identity_id: @identity.id,
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )
  end

  def resolve(resolver)
    resolver.call(provider: "telegram", provider_scope: "global", subject_id: "123456789")
  end
end
