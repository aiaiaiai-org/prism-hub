# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class BindTelegramSurface
      def initialize(resolve_workspace_actor:, binding_repository:)
        @resolve_workspace_actor = resolve_workspace_actor
        @binding_repository = binding_repository
      end

      def call(authorisation_context:, workspace_id:, bot_instance_id:, logical_channel:, chat_id:, message_thread_id:, provider:, provider_scope:, subject_id:)
        actor = @resolve_workspace_actor.call(
          authorisation_context: authorisation_context,
          workspace_id: workspace_id,
          provider: provider,
          provider_scope: provider_scope,
          subject_id: subject_id
        )

        @binding_repository.bind(
          workspace_id: workspace_id,
          bot_instance_id: bot_instance_id,
          logical_channel: logical_channel,
          chat_id: chat_id,
          message_thread_id: message_thread_id,
          actor_user_identity_id: actor.user_identity.id
        )
      end
    end
  end
end
