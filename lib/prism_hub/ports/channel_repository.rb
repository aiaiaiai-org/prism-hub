# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ChannelRepository
      def page(limit:, after_id: nil)
        raise NotImplementedError
      end

      def find(_id)
        raise NotImplementedError
      end
    end
  end
end
