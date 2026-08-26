# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ChannelRepository
      def all
        raise NotImplementedError
      end

      def find(_id)
        raise NotImplementedError
      end
    end
  end
end
