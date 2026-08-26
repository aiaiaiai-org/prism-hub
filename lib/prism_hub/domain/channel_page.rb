# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class ChannelPage
      attr_reader :channels, :next_after_id

      def initialize(channels:, next_after_id: nil)
        unless channels.is_a?(Array) && channels.all? { |channel| channel.is_a?(Channel) }
          raise InputError.new("hub.channels.page.invalid", "channel page contains invalid values")
        end

        @channels = channels.dup.freeze
        @next_after_id = next_after_id&.dup&.freeze
        freeze
      end
    end
  end
end
