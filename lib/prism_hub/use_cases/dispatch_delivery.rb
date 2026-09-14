# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class DispatchDelivery
      def initialize(surface_resolver:, delivery_gateway:)
        @surface_resolver = surface_resolver
        @delivery_gateway = delivery_gateway
      end

      def call(intent:)
        validate_intent!(intent)

        binding = @surface_resolver.call(
          workspace_id: intent.workspace,
          logical_channel: intent.channel
        )
        @delivery_gateway.deliver(intent: intent, binding: binding)
      end

      private

      def validate_intent!(intent)
        return if intent.is_a?(Domain::DeliveryIntent)

        raise InputError.new(
          "hub.delivery.intent.invalid",
          "delivery dispatch requires a DeliveryIntent"
        )
      end
    end
  end
end
