# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class OnboardProviderIdentityTest < Minitest::Test
  Generator = Struct.new(:values) do
    def call
      values.shift || raise("generator exhausted")
    end
  end

  Repository = Struct.new(:membership, :calls, :conflicts, :denied) do
    def resolve_or_create(**arguments)
      calls << arguments
      if denied
        raise PrismHub::IdentityOnboardingDeniedError.new("denied", "denied")
      end
      if conflicts.positive?
        self.conflicts -= 1
        raise PrismHub::PublicUserIdConflictError.new("conflict", "conflict")
      end

      membership
    end
  end

  def setup
    identity = PrismHub::Domain::UserIdentity.new(
      id: "identity-1",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
      status: "active"
    )
    @membership = PrismHub::Domain::WorkspaceMembership.new(
      id: "membership-1",
      workspace_id: "personal-1",
      user_identity: identity,
      role: "owner",
      status: "active"
    )
  end

  def test_returns_workspace_actor_without_exposing_creation_state
    repository = Repository.new(@membership, [], 0, false)
    context = use_case(repository).call(
      authorisation_context: authorisation_context,
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )

    assert_equal "0x0sky", context.user_identity.canonical_identity.id
    assert_equal "personal-1", context.workspace_id
    assert_equal "owner", context.role
    assert_equal "0xfirst", repository.calls.first.fetch(:public_user_id)
  end

  def test_retries_public_user_id_collisions
    repository = Repository.new(@membership, [], 1, false)
    context = use_case(repository, values: %w[0xfirst 0xsecond]).call(
      authorisation_context: authorisation_context,
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )

    assert_equal "0x0sky", context.user_identity.canonical_identity.id
    assert_equal %w[0xfirst 0xsecond], repository.calls.map { |call| call.fetch(:public_user_id) }
  end

  def test_collapses_denied_identity_state_to_actor_authorization_failure
    repository = Repository.new(@membership, [], 0, true)

    error = assert_raises(PrismHub::AuthorisationError) do
      use_case(repository).call(
        authorisation_context: authorisation_context,
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      )
    end

    assert_equal "hub.actor.not_authorized", error.code
  end

  def test_requires_dedicated_machine_capability_before_subject_lookup
    repository = Repository.new(@membership, [], 0, false)
    context = PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-bot",
      capabilities: [],
      allowed_channel_ids: []
    )

    error = assert_raises(PrismHub::AuthorisationError) do
      use_case(repository).call(
        authorisation_context: context,
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      )
    end

    assert_equal "hub.authorization.capability_denied", error.code
    assert_empty repository.calls
  end

  private

  def use_case(repository, values: ["0xfirst"])
    PrismHub::UseCases::OnboardProviderIdentity.new(
      onboarding_repository: repository,
      public_user_id_generator: Generator.new(values)
    )
  end

  def authorisation_context
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-bot",
      capabilities: [PrismHub::Domain::Capabilities::ACTORS_ONBOARD],
      allowed_channel_ids: []
    )
  end
end
