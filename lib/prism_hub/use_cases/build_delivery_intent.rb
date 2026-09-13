# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class BuildDeliveryIntent
      def initialize(porter_gateway:)
        unless porter_gateway.is_a?(Ports::PorterGateway)
          raise ArgumentError, "porter_gateway must be a PorterGateway"
        end

        @porter_gateway = porter_gateway
      end

      def call(artifact:, routes:, chunk_max_chars: nil)
        @porter_gateway.build_delivery_intent(
          artifact: artifact,
          routes: routes,
          chunk_max_chars: chunk_max_chars
        )
      end
    end
  end
end
