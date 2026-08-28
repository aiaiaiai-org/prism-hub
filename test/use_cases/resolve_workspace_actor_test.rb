# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ResolveWorkspaceActorTest < Minitest::Test
  Repository = Struct.new(:value, :calls) do
    def find(**arguments)
      calls << arguments
      value
    end
  end

  def setup
    @identity = PrismHub::Domain::UserIdentity.new(
      id: "identity-1",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
      status: "active"
    )
    @subject = PrismHub::Domain::ProviderSubject.new(
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )
    @binding = PrismHub::Domain::ProviderIdentityBinding.new(
      id: "binding-1",
      user_identity: @identity,
      provider_subject: @subject,
      status: "active"
    )
    @membership = PrismHub::Domain::WorkspaceMembership.new(
      id: "membership-1",
      workspace_id: "personal",
      user_identity: @identity,
      role: "owner",
      status: "active"
    )
    @binding_repository = Repository.new(@binding, [])
    @membership_repository = Repository.new(@membership, [])
    @use_case = PrismHub::UseCases::ResolveWorkspaceActor.new(
      binding_repository: @binding_repository,
      workspace_membership_repository: @membership_repository
    )
  end

  def test_resolves_provider_evidence_into_a_workspace_scoped_actor
    context = @use_case.call(
      authorisation_context: authorisation_context,
      workspace_id: "personal",
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )

    assert_equal "bot-personal", context.principal_id
    assert_equal "personal", context.workspace_id
    assert_equal @identity.canonical_identity, context.user_identity.canonical_identity
    assert_equal "owner", context.role
    assert_equal @subject, context.provider_subject
    assert_equal "personal", @membership_repository.calls.first.fetch(:workspace_id)
  end

  def test_requires_machine_capability_before_repository_lookup
    error = assert_raises(PrismHub::AuthorisationError) do
      @use_case.call(
        authorisation_context: authorisation_context(capabilities: []),
        workspace_id: "personal",
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      )
    end

    assert_equal "hub.authorization.capability_denied", error.code
    assert_empty @binding_repository.calls
    assert_empty @membership_repository.calls
  end

  def test_unknown_provider_subject_does_not_disclose_identity_state
    @binding_repository.value = nil

    error = assert_raises(PrismHub::AuthorisationError) do
      resolve
    end

    assert_equal "hub.actor.not_authorized", error.code
    assert_empty @membership_repository.calls
  end

  def test_revoked_binding_and_missing_membership_share_the_same_public_error
    @binding_repository.value = PrismHub::Domain::ProviderIdentityBinding.new(
      id: "binding-1",
      user_identity: @identity,
      provider_subject: @subject,
      status: "revoked",
      revoked_at: Time.utc(2026, 8, 27, 12, 0, 0)
    )
    revoked_error = assert_raises(PrismHub::AuthorisationError) { resolve }

    @binding_repository.value = @binding
    @membership_repository.value = nil
    missing_membership_error = assert_raises(PrismHub::AuthorisationError) { resolve }

    assert_equal "hub.actor.not_authorized", revoked_error.code
    assert_equal "hub.actor.not_authorized", missing_membership_error.code
  end

  def test_detects_incoherent_repository_results_as_an_internal_invariant_failure
    other_identity = PrismHub::Domain::UserIdentity.new(
      id: "identity-2",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "someone-else"),
      status: "active"
    )
    @membership_repository.value = PrismHub::Domain::WorkspaceMembership.new(
      id: "membership-2",
      workspace_id: "personal",
      user_identity: other_identity,
      role: "member",
      status: "active"
    )

    error = assert_raises(PrismHub::Error) { resolve }

    assert_equal "hub.actor.invariant_violation", error.code
  end

  private

  def resolve
    @use_case.call(
      authorisation_context: authorisation_context,
      workspace_id: "personal",
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )
  end

  def authorisation_context(capabilities: [PrismHub::Domain::Capabilities::ACTORS_RESOLVE])
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "bot-personal",
      capabilities: capabilities,
      allowed_channel_ids: []
    )
  end
end
