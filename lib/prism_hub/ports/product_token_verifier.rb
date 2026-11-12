# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    # Verifies a product token AIS issued for Hub and answers the product's AIS client id, or nil.
    class ProductTokenVerifier
      def verify(token:, now:)
        raise NotImplementedError
      end
    end
  end
end
