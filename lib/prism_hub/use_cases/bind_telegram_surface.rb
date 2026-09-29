# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class BindTelegramSurface
      def initialize(resolve_workspace_actor:, binding_repository:, bot_instance_repository:)
        @resolve_workspace_actor = resolve_workspace_actor
        @binding_repository = binding_repository
        @bot_instance_repository = bot_instance_repository
      end

      # `bot_instance_id` is optional. A client that authenticates as a bot has exactly one
      # instance per workspace, so leaving it out means "mine": the instance is looked up from
      # the credential's principal, and the client never needs an internal identifier.
      def call(authorisation_context:, workspace_id:, logical_channel:, chat_id:, message_thread_id:, provider:, provider_scope:, subject_id:, bot_instance_id: nil)
        actor = @resolve_workspace_actor.call(
          authorisation_context: authorisation_context,
          workspace_id: workspace_id,
          provider: provider,
          provider_scope: provider_scope,
          subject_id: subject_id
        )

        @binding_repository.bind(
          workspace_id: workspace_id,
          bot_instance_id: bot_instance_id || own_bot_instance_id(authorisation_context, workspace_id),
          logical_channel: logical_channel,
          chat_id: chat_id,
          message_thread_id: message_thread_id,
          actor_user_identity_id: actor.user_identity.id
        )
      end

      private

      def own_bot_instance_id(authorisation_context, workspace_id)
        instance = @bot_instance_repository.find(
          principal_id: authorisation_context.principal_id,
          workspace_id: workspace_id
        )
        return instance.id if instance

        raise TelegramSurfaceBindingConflictError.new(
          "hub.telegram_surface_binding.bot_instance_unavailable",
          "the calling bot has no instance in this workspace; read the bot status first"
        )
      end
    end
  end
end
