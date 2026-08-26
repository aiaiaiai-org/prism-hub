# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class SecureRequestIdFactory
      def call
        "hub-#{SecureRandom.uuid}"
      end
    end
  end
end
