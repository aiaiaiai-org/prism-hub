# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ChannelRepository
      def page(limit:, allowed_ids:, after_id: nil)
        raise NotImplementedError
      end

      def all_ids
        raise NotImplementedError
      end

      def find(_id)
        raise NotImplementedError
      end
    end
  end
end
