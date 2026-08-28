# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ServicePrincipalRepository
      def provision(principal_id:, capabilities:, channel_ids:)
        raise NotImplementedError
      end
    end
  end
end
