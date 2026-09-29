# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class PersonalAlertSubscriptionEndpoint
        SUBJECT_FIELDS = %w[provider provider_scope subject_id].freeze
        SAVE_FIELDS = (SUBJECT_FIELDS + %w[cell categories include_nearby]).freeze
        OPERATIONS = %i[status save clear].freeze

        def initialize(subscription:, operation:, request_body:)
          @subscription = subscription
          @operation = operation.to_sym
          @request_body = request_body
          raise ArgumentError, "unsupported alert subscription operation" unless OPERATIONS.include?(@operation)
        end

        def call(request, authorisation_context:)
          payload = valid_shape(@request_body.parse(request))
          arguments = {
            authorisation_context: authorisation_context,
            provider: payload.fetch("provider"),
            provider_scope: payload.fetch("provider_scope"),
            subject_id: payload.fetch("subject_id")
          }
          if @operation == :save
            arguments.merge!(
              cell: payload.fetch("cell"),
              categories: payload.fetch("categories"),
              include_nearby: payload.fetch("include_nearby")
            )
          end

          subscription = @subscription.public_send(@operation, **arguments)
          JsonResponse.call(200, {"alert_subscription" => subscription&.to_h})
        end

        private

        def valid_shape(payload)
          expected = (@operation == :save) ? SAVE_FIELDS : SUBJECT_FIELDS
          subject_strings = SUBJECT_FIELDS.all? { |field| non_empty_string?(payload[field]) }
          return payload if payload.keys.sort == expected.sort && subject_strings

          raise InputError.new(
            "hub.alert_subscription.request.invalid",
            "alert subscription request must contain only #{expected.join(", ")}, with the subject fields as strings"
          )
        end

        def non_empty_string?(value)
          value.is_a?(String) && !value.empty?
        end
      end
    end
  end
end
