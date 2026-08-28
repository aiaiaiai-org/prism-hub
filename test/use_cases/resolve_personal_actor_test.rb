# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ResolvePersonalActorTest < Minitest::Test
  Repository = Struct.new(:value) do
    def find(**)
      value
    end
  end

  WorkspaceIds = Struct.new(:value) do
    def call(_public_user_id)
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
      workspace_id: "personal-1",
      user_identity: @identity,
      role: "owner",
      status: "active"
    )
  end

  def test_resolves_the_existing_personal_workspace_without_creating_state
    context = resolver.call(
      authorisation_context: authorisation_context,
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )

    assert_equal "0x0sky", context.user_identity.canonical_identity.id
    assert_equal "personal-1", context.workspace_id
    assert_equal "owner", context.role
  end

  def test_unknown_binding_and_missing_membership_share_one_denial
    unknown = resolver(binding: nil)
    missing = resolver(membership: nil)

    [unknown, missing].each do |use_case|
      error = assert_raises(PrismHub::AuthorisationError) do
        use_case.call(
          authorisation_context: authorisation_context,
          provider: "telegram",
          provider_scope: "global",
          subject_id: "123456789"
        )
      end
      assert_equal "hub.actor.not_authorized", error.code
    end
  end

  def test_rejects_non_owner_personal_membership_without_disclosure
    member = PrismHub::Domain::WorkspaceMembership.new(
      id: "membership-2",
      workspace_id: "personal-1",
      user_identity: @identity,
      role: "member",
      status: "active"
    )

    error = assert_raises(PrismHub::AuthorisationError) do
      resolver(membership: member).call(
        authorisation_context: authorisation_context,
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      )
    end

    assert_equal "hub.actor.not_authorized", error.code
  end

  def test_requires_actor_resolution_capability_before_lookup
    error = assert_raises(PrismHub::AuthorisationError) do
      resolver.call(
        authorisation_context: PrismHub::Domain::AuthorisationContext.new(
          principal_id: "telegram-bot",
          capabilities: [],
          allowed_channel_ids: []
        ),
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      )
    end

    assert_equal "hub.authorization.capability_denied", error.code
  end

  private

  def resolver(binding: @binding, membership: @membership)
    PrismHub::UseCases::ResolvePersonalActor.new(
      binding_repository: Repository.new(binding),
      workspace_membership_repository: Repository.new(membership),
      workspace_id_factory: WorkspaceIds.new("personal-1")
    )
  end

  def authorisation_context
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-bot",
      capabilities: [PrismHub::Domain::Capabilities::ACTORS_RESOLVE],
      allowed_channel_ids: []
    )
  end
end
