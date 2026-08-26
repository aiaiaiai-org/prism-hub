# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class ChannelsEndpoint
        def initialize(list_channels:)
          @list_channels = list_channels
        end

        def call(_request)
          JsonResponse.call(200, @list_channels.call)
        end
      end
    end
  end
end
