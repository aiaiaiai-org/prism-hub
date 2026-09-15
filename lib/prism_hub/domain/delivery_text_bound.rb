# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    # The number of characters one outgoing message may carry, derived from the
    # targets that will receive it rather than configured next to the queue.
    #
    # With several targets bound to one logical channel the smallest limit wins:
    # a split that fits the narrowest surface fits all of them, while a split
    # sized for the widest cannot be delivered to the rest. An operator override
    # may only lower the result — raising it past what a surface accepts produces
    # messages that surface will always reject.
    class DeliveryTextBound
      SUPPORTED_RANGE = (64..100_000).freeze

      def self.for(targets:, override: nil)
        limits = Array(targets).map { text_max_chars(_1) }
        if limits.empty?
          raise InputError.new(
            "hub.delivery.text_bound.targets.missing",
            "a delivery text bound requires at least one target"
          )
        end

        bound = limits.min
        bound = [bound, validated_override(override)].min unless override.nil?
        bound
      end

      def self.text_max_chars(target)
        value = target.respond_to?(:text_max_chars) ? target.text_max_chars : nil
        return value if value.is_a?(Integer) && SUPPORTED_RANGE.cover?(value)

        raise InputError.new(
          "hub.delivery.text_bound.target.invalid",
          "each delivery target must expose a text_max_chars within #{SUPPORTED_RANGE}"
        )
      end
      private_class_method :text_max_chars

      def self.validated_override(value)
        return value if value.is_a?(Integer) && SUPPORTED_RANGE.cover?(value)

        raise InputError.new(
          "hub.delivery.text_bound.override.invalid",
          "a delivery text bound override must be an integer within #{SUPPORTED_RANGE}"
        )
      end
      private_class_method :validated_override
    end
  end
end
