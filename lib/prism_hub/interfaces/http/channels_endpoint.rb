# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class ChannelsEndpoint
        DEFAULT_LIMIT = 50
        MAX_LIMIT = 100

        def initialize(list_channels:, cursor: ChannelCursor.new)
          @list_channels = list_channels
          @cursor = cursor
        end

        def call(request, authorisation_context:)
          limit = limit(request.params["limit"])
          result = @list_channels.call(
            authorisation_context: authorisation_context,
            limit: limit,
            after_id: @cursor.decode(request.params["cursor"])
          )
          JsonResponse.call(
            200,
            {
              "channels" => result.fetch("channels"),
              "page" => {
                "limit" => limit,
                "next_cursor" => @cursor.encode(result.fetch("next_after_id"))
              }
            }
          )
        end

        private

        def limit(value)
          return DEFAULT_LIMIT if value.nil?

          number = Integer(value, 10)
          return number if number.between?(1, MAX_LIMIT)

          raise ArgumentError
        rescue ArgumentError
          raise InputError.new(
            "hub.channels.limit.invalid",
            "limit must be an integer between 1 and #{MAX_LIMIT}"
          )
        end
      end
    end
  end
end
