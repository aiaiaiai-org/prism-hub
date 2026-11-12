# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ServicePrincipalRepository
      def provision(principal_id:, capabilities:, channel_ids:, product_id: nil)
        raise NotImplementedError
      end

      # The authorisation context of the active principal bound to this AIS product, or nil.
      def authorise_product(product_id:)
        raise NotImplementedError
      end
    end
  end
end
