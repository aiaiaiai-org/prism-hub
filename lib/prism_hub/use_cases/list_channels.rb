# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ListChannels
      def initialize(channel_repository:)
        @channel_repository = channel_repository
      end

      def call
        {
          "channels" => @channel_repository.all.map(&:public_attributes)
        }
      end
    end
  end
end
