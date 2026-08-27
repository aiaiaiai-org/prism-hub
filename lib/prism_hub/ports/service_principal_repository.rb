# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ServicePrincipalRepository
      def provision(workspace_id:, principal_id:, bot_instance_id:, capabilities:, channel_ids:)
        raise NotImplementedError
      end
    end
  end
end
