# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    # Persistence of one alert subscription per workspace.
    #
    # Only the workspace owner may change it. `clear` deletes the row: nothing about where a
    # person was is kept once they ask to stop.
    class AlertSubscriptionRepository
      def find(workspace_id:)
        raise NotImplementedError
      end

      def save(workspace_id:, actor_user_identity_id:, cell:, categories:, include_nearby:, occurred_at:)
        raise NotImplementedError
      end

      def clear(workspace_id:, actor_user_identity_id:, occurred_at:)
        raise NotImplementedError
      end

      # Subscriptions standing in one of `cells` that asked about `category`.
      def covering(cells:, category:)
        raise NotImplementedError
      end

      def find_all(workspace_ids:)
        raise NotImplementedError
      end
    end
  end
end
