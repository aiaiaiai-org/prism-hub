# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class HealthEndpoint
        def call(_request)
          JsonResponse.call(
            200,
            {"status" => "ok", "service" => "prism-hub"}
          )
        end
      end
    end
  end
end
