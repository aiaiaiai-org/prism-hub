# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class PersonalBotLifecycle
      def initialize(resolve_personal_actor:, bot_instance_repository:, clock:)
        @resolve_personal_actor = resolve_personal_actor
        @bot_instance_repository = bot_instance_repository
        @clock = clock
      end

      def status(authorisation_context:, provider:, provider_scope:, subject_id:)
        require_capability!(authorisation_context, Domain::Capabilities::BOT_INSTANCES_READ)
        actor = resolve_actor(authorisation_context, provider, provider_scope, subject_id)
        call_repository(:ensure, actor)
      end

      def pause(authorisation_context:, provider:, provider_scope:, subject_id:)
        require_capability!(authorisation_context, Domain::Capabilities::BOT_INSTANCES_MANAGE)
        actor = resolve_actor(authorisation_context, provider, provider_scope, subject_id)
        call_repository(:pause, actor)
      end

      def resume(authorisation_context:, provider:, provider_scope:, subject_id:)
        require_capability!(authorisation_context, Domain::Capabilities::BOT_INSTANCES_MANAGE)
        actor = resolve_actor(authorisation_context, provider, provider_scope, subject_id)
        call_repository(:resume, actor)
      end

      private

      def require_capability!(authorisation_context, capability)
        unless authorisation_context.is_a?(Domain::AuthorisationContext)
          raise ArgumentError, "authorisation_context must be an AuthorisationContext"
        end
        return if authorisation_context.allows_capability?(capability)

        raise AuthorisationError.new(
          "hub.authorization.capability_denied",
          "the authenticated principal cannot perform this bot lifecycle operation"
        )
      end

      def resolve_actor(authorisation_context, provider, provider_scope, subject_id)
        @resolve_personal_actor.call(
          authorisation_context: authorisation_context,
          provider: provider,
          provider_scope: provider_scope,
          subject_id: subject_id
        )
      end

      def call_repository(operation, actor)
        @bot_instance_repository.public_send(
          operation,
          principal_id: actor.principal_id,
          workspace_id: actor.workspace_id,
          actor_user_identity_id: actor.user_identity.id,
          occurred_at: @clock.call
        )
      rescue BotInstanceConflictError => error
        raise unless error.code == "hub.bot_instance.owner_required"

        raise AuthorisationError.new(
          "hub.actor.not_authorized",
          "the provider subject is not authorized for a personal workspace"
        )
      end
    end
  end
end
