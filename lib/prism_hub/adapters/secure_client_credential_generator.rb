# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class SecureClientCredentialGenerator
      PREFIX = "prism_client_v1_".freeze
      RANDOM_BYTES = 32

      def call
        "#{PREFIX}#{SecureRandom.urlsafe_base64(RANDOM_BYTES, false)}".freeze
      end
    end
  end
end
