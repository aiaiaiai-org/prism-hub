# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class BotInstanceRepository
      def ensure(principal_id:, workspace_id:, actor_user_identity_id:, occurred_at:)
        raise NotImplementedError
      end

      def find(principal_id:, workspace_id:)
        raise NotImplementedError
      end

      def pause(principal_id:, workspace_id:, actor_user_identity_id:, occurred_at:)
        raise NotImplementedError
      end

      def resume(principal_id:, workspace_id:, actor_user_identity_id:, occurred_at:)
        raise NotImplementedError
      end
    end
  end
end
