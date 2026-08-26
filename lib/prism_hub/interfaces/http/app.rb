# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class App
        API_PATHS = %w[
          /api/v1/channels
          /api/v1/publications
          /api/v1/publications/validate
        ].freeze

        def initialize(authenticator:, health_endpoint:, routes:, logger:)
          @authenticator = authenticator
          @health_endpoint = health_endpoint
          @routes = routes.freeze
          @logger = logger
        end

        def call(environment)
          request = Rack::Request.new(environment)
          return @health_endpoint.call(request) if health_request?(request)
          return unauthorized unless @authenticator.authorized?(request)

          endpoint = @routes[[request.request_method, request.path_info]]
          return endpoint.call(request) if endpoint
          return method_not_allowed if API_PATHS.include?(request.path_info)

          JsonResponse.error(404, "hub.http.not_found", "endpoint not found")
        rescue InputError, UnknownChannelError => error
          JsonResponse.error(
            input_status(error),
            error.code,
            error.message,
            details: error.details
          )
        rescue ExecutionUnavailableError => error
          JsonResponse.error(503, error.code, error.message)
        rescue StandardError => error
          @logger.error("hub_request_failed error_class=#{error.class.name}")
          JsonResponse.error(
            500,
            "hub.internal",
            "an unexpected internal error occurred"
          )
        end

        private

        def health_request?(request)
          request.get? && request.path_info == "/healthz"
        end

        def unauthorized
          JsonResponse.error(
            401,
            "hub.authorization.required",
            "a valid Hub bearer token is required"
          )
        end

        def method_not_allowed
          JsonResponse.error(
            405,
            "hub.http.method_not_allowed",
            "HTTP method is not supported for this endpoint"
          )
        end

        def input_status(error)
          case error.code
          when "hub.http.body.invalid_json"
            400
          when "hub.http.body.too_large"
            413
          when "hub.http.content_type.unsupported"
            415
          else
            422
          end
        end
      end
    end
  end
end
