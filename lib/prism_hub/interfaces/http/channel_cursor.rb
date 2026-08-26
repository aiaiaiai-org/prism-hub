# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class ChannelCursor
        PREFIX = "channel:".freeze

        def encode(channel_id)
          return nil if channel_id.nil?

          Base64.urlsafe_encode64("#{PREFIX}#{channel_id}", padding: false).freeze
        end

        def decode(value)
          return nil if value.nil? || value.empty?

          decoded = Base64.urlsafe_decode64(padded(value))
          unless decoded.start_with?(PREFIX)
            raise ArgumentError
          end

          channel_id = decoded.delete_prefix(PREFIX)
          return channel_id.freeze if Domain::Channel::REFERENCE_PATTERN.match?(channel_id)

          raise ArgumentError
        rescue ArgumentError
          raise InputError.new(
            "hub.channels.cursor.invalid",
            "cursor is not a valid channel page cursor"
          )
        end

        private

        def padded(value)
          source = String(value)
          source + ("=" * ((4 - (source.length % 4)) % 4))
        end
      end
    end
  end
end
