# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ListChannels
      def initialize(channel_repository:)
        @channel_repository = channel_repository
      end

      def call(limit:, after_id: nil)
        page = @channel_repository.page(limit: limit, after_id: after_id)
        {
          "channels" => page.channels.map(&:public_attributes),
          "next_after_id" => page.next_after_id
        }
      end
    end
  end
end
