# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class PublicationEndpoint
        ERROR_STATUS = {
          "invalid_envelope" => 422,
          "invalid_request" => 422,
          "provider_not_found" => 422,
          "unsupported_protocol" => 502,
          "capability_discovery_failed" => 502,
          "internal" => 502
        }.freeze

        def initialize(execute_publication:, request_body:)
          @execute_publication = execute_publication
          @request_body = request_body
        end

        def call(request)
          idempotency_key = request.get_header("HTTP_IDEMPOTENCY_KEY")
          draft = Domain::PublicationDraft.from_hash(@request_body.parse(request))
          response = @execute_publication.call(
            draft: draft,
            idempotency_key: idempotency_key
          )
          JsonResponse.call(status_for(response), response)
        end

        private

        def status_for(response)
          return 200 if response["status"] == "ok"

          code = response.dig("error", "code")
          ERROR_STATUS.fetch(code, 502)
        end
      end
    end
  end
end
