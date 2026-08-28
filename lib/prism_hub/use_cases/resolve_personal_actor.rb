# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ResolvePersonalActor
      ROLE_OWNER = "owner".freeze

      def initialize(binding_repository:, workspace_membership_repository:, workspace_id_factory:)
        @binding_repository = binding_repository
        @workspace_membership_repository = workspace_membership_repository
        @workspace_id_factory = workspace_id_factory
      end

      def call(authorisation_context:, provider:, provider_scope:, subject_id:)
        validate_context!(authorisation_context)
        require_capability!(authorisation_context)
        provider_subject = Domain::ProviderSubject.new(
          provider: provider,
          provider_scope: provider_scope,
          subject_id: subject_id
        )

        binding = @binding_repository.find(provider_subject: provider_subject)
        deny_actor! unless binding&.active? && binding.user_identity.active?

        workspace_id = @workspace_id_factory.call(binding.user_identity.canonical_identity.id)
        membership = @workspace_membership_repository.find(
          user_identity_id: binding.user_identity.id,
          workspace_id: workspace_id
        )
        deny_actor! unless membership&.active? && membership.user_identity.active? && membership.role == ROLE_OWNER
        verify_coherence!(workspace_id, binding, membership)

        Domain::WorkspaceActorContext.new(
          principal_id: authorisation_context.principal_id,
          workspace_id: workspace_id,
          user_identity: binding.user_identity,
          role: membership.role,
          provider_subject: provider_subject
        )
      rescue InputError => error
        raise if error.code.start_with?("hub.provider_subject.")

        deny_actor!
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
          "the provider subject is not authorized for a personal workspace"
        )
      end

      def verify_coherence!(workspace_id, binding, membership)
        coherent = membership.workspace_id == workspace_id &&
          membership.user_identity.id == binding.user_identity.id &&
          membership.user_identity.canonical_identity == binding.user_identity.canonical_identity
        return if coherent

        deny_actor!
      end
    end
  end
end
