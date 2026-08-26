# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class Channel
      REFERENCE_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\z/
      PROVIDER_PATTERN = /\A[a-z0-9]+(?:[._-][a-z0-9]+)+\z/

      attr_reader :id, :label, :provider_id, :channel_ref, :credential_ref

      def initialize(id:, label:, provider_id:, channel_ref:, credential_ref: nil)
        @id = required_reference(id, "id")
        @label = required_label(label)
        @provider_id = required_provider(provider_id)
        @channel_ref = required_reference(channel_ref, "channel_ref")
        @credential_ref = optional_reference(credential_ref, "credential_ref")
        freeze
      end

      def public_attributes
        {
          "id" => id,
          "label" => label,
          "provider_id" => provider_id
        }.freeze
      end

      def prism_target(target_id:, selection:)
        target = {
          "id" => target_id,
          "provider_id" => provider_id,
          "channel" => channel_ref,
          "selection" => selection
        }
        target["credential"] = credential_ref if credential_ref
        target
      end

      private

      def required_reference(value, field)
        string = String(value)
        return string.freeze if REFERENCE_PATTERN.match?(string)

        raise InputError.new(
          "hub.channel.#{field}.invalid",
          "#{field} must be a non-empty stable reference"
        )
      end

      def optional_reference(value, field)
        return nil if value.nil?

        required_reference(value, field)
      end

      def required_provider(value)
        string = String(value)
        return string.freeze if PROVIDER_PATTERN.match?(string)

        raise InputError.new(
          "hub.channel.provider_id.invalid",
          "provider_id must be a namespaced provider reference"
        )
      end

      def required_label(value)
        string = String(value).strip
        return string.freeze if string.length.between?(1, 120)

        raise InputError.new(
          "hub.channel.label.invalid",
          "label must contain between 1 and 120 characters"
        )
      end
    end
  end
end
