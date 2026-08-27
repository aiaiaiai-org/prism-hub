# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ResolveWorkspaceActor
      def initialize(binding_repository:, workspace_membership_repository:)
        @binding_repository = binding_repository
        @workspace_membership_repository = workspace_membership_repository
      end

      def call(authorisation_context:, provider:, provider_scope:, subject_id:)
        validate_context!(authorisation_context)
        provider_subject = Domain::ProviderSubject.new(
          provider: provider,
          provider_scope: provider_scope,
          subject_id: subject_id
        )
        require_capability!(authorisation_context)

        binding = @binding_repository.find(provider_subject: provider_subject)
        deny_actor! unless binding&.active? && binding.user_identity.active?

        membership = @workspace_membership_repository.find(
          user_identity_id: binding.user_identity.id,
          workspace_id: authorisation_context.workspace_id
        )
        deny_actor! unless membership&.active? && membership.user_identity.active?
        verify_coherence!(authorisation_context, binding, membership)

        Domain::WorkspaceActorContext.new(
          principal_id: authorisation_context.principal_id,
          workspace_id: authorisation_context.workspace_id,
          user_identity: binding.user_identity,
          role: membership.role,
          provider_subject: provider_subject
        )
      end

      private

      def validate_context!(authorisation_context)
        return if authorisation_context.is_a?(Domain::AuthorisationContext)

        raise ArgumentError, "authorisation_context must be an AuthorisationContext"
      end

      def require_capability!(authorisation_context)
        return if authorisation_context.allows_capability?(Domain::Capabilities::ACTORS_RESOLVE)

        raise AuthorisationError.new(
          "hub.authorization.capability_denied",
          "the authenticated principal cannot resolve human actors"
        )
      end

      def deny_actor!
        raise AuthorisationError.new(
          "hub.actor.not_authorized",
          "the provider subject is not authorized for this workspace"
        )
      end

      def verify_coherence!(authorisation_context, binding, membership)
        coherent = membership.workspace_id == authorisation_context.workspace_id &&
          membership.user_identity.id == binding.user_identity.id &&
          membership.user_identity.canonical_identity == binding.user_identity.canonical_identity
        return if coherent

        raise Error.new(
          "hub.actor.invariant_violation",
          "resolved identity and workspace membership are inconsistent"
        )
      end
    end
  end
end
