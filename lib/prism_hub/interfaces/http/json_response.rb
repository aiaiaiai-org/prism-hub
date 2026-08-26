# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      module JsonResponse
        HEADERS = {
          "content-type" => "application/json; charset=utf-8",
          "cache-control" => "no-store"
        }.freeze

        module_function

        def call(status, payload)
          body = JSON.generate(payload)
          [
            status,
            HEADERS.merge("content-length" => body.bytesize.to_s),
            [body]
          ]
        end

        def error(status, code, message, details: nil)
          error = {"code" => code, "message" => message}
          error["details"] = details if details
          call(status, {"status" => "error", "error" => error})
        end
      end
    end
  end
end
