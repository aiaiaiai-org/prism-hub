# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class App
        REQUEST_ID_KEY = "prism_hub.request_id".freeze
        API_PATHS = %w[
          /api/v1/channels
          /api/v1/publications
          /api/v1/publications/validate
        ].freeze

        def initialize(authenticator:, health_endpoint:, routes:, logger:, request_id_factory:)
          @authenticator = authenticator
          @health_endpoint = health_endpoint
          @routes = routes.freeze
          @logger = logger
          @request_id_factory = request_id_factory
        end

        def call(environment)
          request_id = @request_id_factory.call
          environment[REQUEST_ID_KEY] = request_id
          response = dispatch(Rack::Request.new(environment), request_id)
          with_request_id(response, request_id)
        end

        private

        def dispatch(request, request_id)
          return @health_endpoint.call(request) if health_request?(request)
          return unauthorized(request_id) unless @authenticator.authorized?(request)

          endpoint = @routes[[request.request_method, request.path_info]]
          return endpoint.call(request) if endpoint
          return method_not_allowed(request_id) if API_PATHS.include?(request.path_info)

          JsonResponse.error(
            404,
            "hub.http.not_found",
            "endpoint not found",
            request_id: request_id
          )
        rescue InputError, UnknownChannelError => error
          JsonResponse.error(
            input_status(error),
            error.code,
            error.message,
            details: error.details,
            request_id: request_id
          )
        rescue ExecutionUnavailableError => error
          JsonResponse.error(503, error.code, error.message, request_id: request_id)
        rescue StandardError => error
          @logger.error("hub_request_failed request_id=#{request_id} error_class=#{error.class.name}")
          JsonResponse.error(
            500,
            "hub.internal",
            "an unexpected internal error occurred",
            request_id: request_id
          )
        end

        def health_request?(request)
          request.get? && request.path_info == "/healthz"
        end

        def unauthorized(request_id)
          JsonResponse.error(
            401,
            "hub.authorization.required",
            "a valid Hub bearer token is required",
            request_id: request_id
          )
        end

        def method_not_allowed(request_id)
          JsonResponse.error(
            405,
            "hub.http.method_not_allowed",
            "HTTP method is not supported for this endpoint",
            request_id: request_id
          )
        end

        def with_request_id(response, request_id)
          status, headers, body = response
          [status, headers.merge("x-request-id" => request_id), body]
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
