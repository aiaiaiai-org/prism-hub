# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class PersonalBotLifecycleEndpoint
        REQUIRED_FIELDS = %w[provider provider_scope subject_id].freeze
        OPERATIONS = %i[status pause resume].freeze

        def initialize(lifecycle:, operation:, request_body:)
          @lifecycle = lifecycle
          @operation = operation.to_sym
          @request_body = request_body
          raise ArgumentError, "unsupported bot lifecycle operation" unless OPERATIONS.include?(@operation)
        end

        def call(request, authorisation_context:)
          subject = provider_subject(@request_body.parse(request))
          instance = @lifecycle.public_send(
            @operation,
            authorisation_context: authorisation_context,
            provider: subject.fetch("provider"),
            provider_scope: subject.fetch("provider_scope"),
            subject_id: subject.fetch("subject_id")
          )

          JsonResponse.call(200, {"bot_instance" => {"status" => instance.status}})
        end

        private

        def provider_subject(payload)
          valid_shape = payload.keys.sort == REQUIRED_FIELDS.sort &&
            REQUIRED_FIELDS.all? { |field| non_empty_string?(payload[field]) }
          return payload if valid_shape

          raise InputError.new(
            "hub.bot_instance.request.invalid",
            "bot lifecycle request must contain only provider, provider_scope, and subject_id strings"
          )
        end

        def non_empty_string?(value)
          value.is_a?(String) && !value.empty?
        end
      end
    end
  end
end
