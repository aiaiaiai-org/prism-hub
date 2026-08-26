# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class EnvironmentChannelRepository < Ports::ChannelRepository
      CHANNEL_KEYS = %w[channel_ref credential_ref id label provider_id].freeze

      def initialize(source)
        values = parse(source)
        @channels = values.to_h do |value|
          channel = build_channel(value)
          [channel.id, channel]
        end
        if @channels.length != values.length
          raise ConfigurationError.new(
            "hub.channels.duplicate",
            "configured channel ids must be unique"
          )
        end
        @channels.freeze
      end

      def all
        @channels.values
      end

      def find(id)
        @channels[id]
      end

      private

      def parse(source)
        value = JSON.parse(source)
        return value if value.is_a?(Array)

        raise ConfigurationError.new(
          "hub.channels.invalid",
          "PRISM_HUB_CHANNELS_JSON must contain a JSON array"
        )
      rescue JSON::ParserError
        raise ConfigurationError.new(
          "hub.channels.invalid_json",
          "PRISM_HUB_CHANNELS_JSON must contain valid JSON"
        )
      end

      def build_channel(value)
        unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
          raise ConfigurationError.new(
            "hub.channel.invalid",
            "every configured channel must be a JSON object"
          )
        end

        unknown = value.keys - CHANNEL_KEYS
        if unknown.any?
          raise ConfigurationError.new(
            "hub.channel.field.unknown",
            "configured channel contains unsupported fields",
            details: {"fields" => unknown.sort}
          )
        end

        Domain::Channel.new(
          id: value.fetch("id"),
          label: value.fetch("label"),
          provider_id: value.fetch("provider_id"),
          channel_ref: value.fetch("channel_ref"),
          credential_ref: value["credential_ref"]
        )
      rescue KeyError => error
        raise ConfigurationError.new(
          "hub.channel.field.required",
          "configured channel is missing #{error.key}"
        )
      rescue InputError => error
        raise ConfigurationError.new(error.code, error.message, details: error.details)
      end
    end
  end
end
