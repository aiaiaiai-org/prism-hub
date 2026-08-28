# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class AuthorisationContext
      CAPABILITY_PATTERN = /\A[a-z][a-z0-9._-]*:[a-z][a-z0-9._-]*\z/

      attr_reader :principal_id, :capabilities, :allowed_channel_ids

      def initialize(principal_id:, capabilities:, allowed_channel_ids:)
        @principal_id = reference(principal_id, "principal_id")
        @capabilities = capability_set(capabilities)
        @allowed_channel_ids = reference_set(allowed_channel_ids, "allowed_channel_ids")
        freeze
      end

      def allows_capability?(capability)
        @capabilities.include?(capability)
      end

      def allows_channel?(channel_id)
        @allowed_channel_ids.include?(channel_id)
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze if Channel::REFERENCE_PATTERN.match?(string)

        raise InputError.new(
          "hub.authorisation.#{field}.invalid",
          "#{field} must be a non-empty stable reference"
        )
      end

      def capability_set(values)
        normalized = Array(values).map do |value|
          string = String(value)
          unless CAPABILITY_PATTERN.match?(string)
            raise InputError.new(
              "hub.authorisation.capability.invalid",
              "capabilities must use namespace:action references"
            )
          end
          string.freeze
        end
        normalized.uniq.sort.freeze
      end

      def reference_set(values, field)
        Array(values).map { |value| reference(value, field) }.uniq.sort.freeze
      end
    end
  end
end
