# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class RequestBody
        def initialize(max_bytes: 1_048_576)
          @max_bytes = max_bytes
        end

        def parse(request)
          unless request.media_type == "application/json"
            raise InputError.new(
              "hub.http.content_type.unsupported",
              "Content-Type must be application/json"
            )
          end

          source = request.body.read(@max_bytes + 1)
          if source.bytesize > @max_bytes
            raise InputError.new(
              "hub.http.body.too_large",
              "request body exceeded the configured limit"
            )
          end

          value = JSON.parse(source)
          return value if value.is_a?(Hash)

          raise InputError.new(
            "hub.http.body.invalid",
            "request body must contain a JSON object"
          )
        rescue JSON::ParserError
          raise InputError.new(
            "hub.http.body.invalid_json",
            "request body must contain valid JSON"
          )
        ensure
          request.body.rewind if request.body.respond_to?(:rewind)
        end
      end
    end
  end
end
