# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class OnboardProviderIdentity
      MAX_ALLOCATION_ATTEMPTS = 8

      def initialize(onboarding_repository:, public_user_id_generator:)
        @onboarding_repository = onboarding_repository
        @public_user_id_generator = public_user_id_generator
      end

      def call(authorisation_context:, provider:, provider_scope:, subject_id:)
        validate_context!(authorisation_context)
        require_capability!(authorisation_context)
        provider_subject = Domain::ProviderSubject.new(
          provider: provider,
          provider_scope: provider_scope,
          subject_id: subject_id
        )

        MAX_ALLOCATION_ATTEMPTS.times do
          membership = @onboarding_repository.resolve_or_create(
            provider_subject: provider_subject,
            public_user_id: @public_user_id_generator.call
          )
          return actor_context(authorisation_context, provider_subject, membership)
        rescue PublicUserIdConflictError
          next
        rescue IdentityOnboardingDeniedError
          deny_actor!
        end

        raise Error.new(
          "hub.identity_onboarding.unavailable",
          "a public user id could not be allocated"
        )
      end

      private

      def actor_context(authorisation_context, provider_subject, membership)
        Domain::WorkspaceActorContext.new(
          principal_id: authorisation_context.principal_id,
          workspace_id: membership.workspace_id,
          user_identity: membership.user_identity,
          role: membership.role,
          provider_subject: provider_subject
        )
      end

      def validate_context!(authorisation_context)
        return if authorisation_context.is_a?(Domain::AuthorisationContext)

        raise ArgumentError, "authorisation_context must be an AuthorisationContext"
      end

      def require_capability!(authorisation_context)
        return if authorisation_context.allows_capability?(Domain::Capabilities::ACTORS_ONBOARD)

        raise AuthorisationError.new(
          "hub.authorization.capability_denied",
          "the authenticated principal cannot onboard human actors"
        )
      end

      def deny_actor!
        raise AuthorisationError.new(
          "hub.actor.not_authorized",
          "the provider subject cannot be onboarded"
        )
      end
    end
  end
end
