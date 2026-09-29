# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    # Reads, sets, and clears the alert subscription of the person a provider subject resolves to.
    #
    # The machine principal needs `alert_subscriptions:read` or `alert_subscriptions:manage`, on top
    # of the `actors:resolve` that resolving the person needs. The person must be the active owner
    # of their personal workspace.
    class PersonalAlertSubscription
      def initialize(resolve_personal_actor:, alert_subscription_repository:, clock:)
        @resolve_personal_actor = resolve_personal_actor
        @alert_subscription_repository = alert_subscription_repository
        @clock = clock
      end

      def status(authorisation_context:, provider:, provider_scope:, subject_id:)
        require_capability!(authorisation_context, Domain::Capabilities::ALERT_SUBSCRIPTIONS_READ)
        actor = resolve_actor(authorisation_context, provider, provider_scope, subject_id)
        @alert_subscription_repository.find(workspace_id: actor.workspace_id)
      end

      def save(authorisation_context:, provider:, provider_scope:, subject_id:, cell:, categories:, include_nearby:)
        require_capability!(authorisation_context, Domain::Capabilities::ALERT_SUBSCRIPTIONS_MANAGE)
        actor = resolve_actor(authorisation_context, provider, provider_scope, subject_id)
        occurred_at = @clock.call
        # Built first so an invalid cell, category, or flag is rejected before anything is stored.
        subscription = Domain::AlertSubscription.new(
          workspace_id: actor.workspace_id,
          cell: cell,
          categories: categories,
          include_nearby: include_nearby,
          updated_at: occurred_at
        )
        call_repository do
          @alert_subscription_repository.save(
            workspace_id: actor.workspace_id,
            actor_user_identity_id: actor.user_identity.id,
            cell: subscription.cell,
            categories: subscription.categories,
            include_nearby: subscription.include_nearby,
            occurred_at: occurred_at
          )
        end
      end

      def clear(authorisation_context:, provider:, provider_scope:, subject_id:)
        require_capability!(authorisation_context, Domain::Capabilities::ALERT_SUBSCRIPTIONS_MANAGE)
        actor = resolve_actor(authorisation_context, provider, provider_scope, subject_id)
        call_repository do
          @alert_subscription_repository.clear(
            workspace_id: actor.workspace_id,
            actor_user_identity_id: actor.user_identity.id,
            occurred_at: @clock.call
          )
        end
        nil
      end

      private

      def require_capability!(authorisation_context, capability)
        unless authorisation_context.is_a?(Domain::AuthorisationContext)
          raise ArgumentError, "authorisation_context must be an AuthorisationContext"
        end
        return if authorisation_context.allows_capability?(capability)

        raise AuthorisationError.new(
          "hub.authorization.capability_denied",
          "the authenticated principal cannot perform this alert subscription operation"
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

      def call_repository
        yield
      rescue AlertSubscriptionConflictError => error
        raise unless error.code == "hub.alert_subscription.owner_required"

        raise AuthorisationError.new(
          "hub.actor.not_authorized",
          "the provider subject is not authorized for a personal workspace"
        )
      end
    end
  end
end
