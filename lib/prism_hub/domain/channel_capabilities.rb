# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class ChannelCapabilities
      FORMATS = %w[post story short_video poll].freeze
      MEDIA_KINDS = %w[image video audio document].freeze
      KEYS = %w[formats media_kinds text].freeze

      attr_reader :formats, :media_kinds

      def self.from_hash(value)
        unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
          raise InputError.new(
            "hub.channel.capabilities.invalid",
            "capabilities must be a JSON object"
          )
        end

        unknown = value.keys - KEYS
        if unknown.any?
          raise InputError.new(
            "hub.channel.capabilities.field.unknown",
            "capabilities contain unsupported fields",
            details: {"fields" => unknown.sort}
          )
        end

        new(
          formats: value.fetch("formats"),
          media_kinds: value.fetch("media_kinds", []),
          text: value.fetch("text")
        )
      rescue KeyError => error
        raise InputError.new(
          "hub.channel.capabilities.field.required",
          "capabilities are missing #{error.key}"
        )
      end

      def initialize(formats:, media_kinds:, text:)
        @formats = enum_values(formats, FORMATS, "formats")
        @media_kinds = enum_values(media_kinds, MEDIA_KINDS, "media_kinds", allow_empty: true)
        @text = boolean(text)
        if !@text && @media_kinds.empty?
          raise InputError.new(
            "hub.channel.capabilities.content.empty",
            "capabilities must support text or at least one media kind"
          )
        end
        freeze
      end

      def text?
        @text
      end

      def public_attributes
        {
          "formats" => formats,
          "text" => text?,
          "media_kinds" => media_kinds
        }.freeze
      end

      private

      def enum_values(values, allowed, field, allow_empty: false)
        unless values.is_a?(Array) && values.all? { |value| value.is_a?(String) }
          invalid!(field, allowed)
        end

        normalized = values.uniq.sort
        invalid!(field, allowed) if (!allow_empty && normalized.empty?) || (normalized - allowed).any?
        normalized.map!(&:freeze)
        normalized.freeze
      end

      def boolean(value)
        return value if value == true || value == false

        raise InputError.new(
          "hub.channel.capabilities.text.invalid",
          "capabilities text must be a boolean"
        )
      end

      def invalid!(field, allowed)
        raise InputError.new(
          "hub.channel.capabilities.#{field}.invalid",
          "capabilities #{field} must contain unique supported values",
          details: {"allowed" => allowed}
        )
      end
    end
  end
end
