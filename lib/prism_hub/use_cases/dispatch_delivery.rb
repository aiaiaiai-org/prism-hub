# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class DispatchDelivery
      def initialize(surface_resolver:, delivery_gateway:, build_delivery_intent:)
        @surface_resolver = surface_resolver
        @delivery_gateway = delivery_gateway
        @build_delivery_intent = build_delivery_intent
      end

      def call(request:)
        validate_request!(request)

        binding = @surface_resolver.call(
          workspace_id: request.workspace,
          logical_channel: request.channel
        )
        intent = @build_delivery_intent.call(
          artifact: request.artifact,
          routes: request.routes,
          chunk_max_chars: Domain::DeliveryTextBound.for(
            targets: [binding],
            override: request.chunk_max_chars_limit
          )
        )
        @delivery_gateway.deliver(intent: intent, binding: binding)
      end

      private

      def validate_request!(request)
        return if request.is_a?(Domain::DeliveryRequest)

        raise InputError.new(
          "hub.delivery.request.invalid",
          "delivery dispatch requires a DeliveryRequest"
        )
      end
    end
  end
end
