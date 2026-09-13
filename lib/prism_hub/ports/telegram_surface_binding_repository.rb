# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class TelegramSurfaceBindingRepository
      def bind(
        workspace_id:,
        bot_instance_id:,
        logical_channel:,
        chat_id:,
        message_thread_id:,
        actor_user_identity_id:
      )
        raise NotImplementedError
      end

      def find_by_logical_context(workspace_id:, logical_channel:)
        raise NotImplementedError
      end

      def find_by_surface(bot_instance_id:, chat_id:, message_thread_id:)
        raise NotImplementedError
      end

      def revoke(id:, actor_user_identity_id:, revoked_at:)
        raise NotImplementedError
      end
    end
  end
end
