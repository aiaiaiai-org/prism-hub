# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class ActorResolutionEndpoint
        REQUIRED_FIELDS = %w[workspace_id provider provider_scope subject_id].freeze

        def initialize(resolve_workspace_actor:, request_body:)
          @resolve_workspace_actor = resolve_workspace_actor
          @request_body = request_body
        end

        def call(request, authorisation_context:)
          subject = actor_subject(@request_body.parse(request))
          context = @resolve_workspace_actor.call(
            authorisation_context: authorisation_context,
            workspace_id: subject.fetch("workspace_id"),
            provider: subject.fetch("provider"),
            provider_scope: subject.fetch("provider_scope"),
            subject_id: subject.fetch("subject_id")
          )
          identity = context.user_identity.canonical_identity

          JsonResponse.call(
            200,
            {
              "actor" => {
                "identity" => {"type" => identity.type, "id" => identity.id},
                "role" => context.role
              }
            }
          )
        end

        private

        def actor_subject(payload)
          valid_shape = payload.keys.sort == REQUIRED_FIELDS.sort &&
            REQUIRED_FIELDS.all? { |field| non_empty_string?(payload[field]) }
          return payload if valid_shape

          raise InputError.new(
            "hub.actor.request.invalid",
            "actor request must contain only workspace_id, provider, provider_scope, and subject_id strings"
          )
        end

        def non_empty_string?(value)
          value.is_a?(String) && !value.empty?
        end
      end
    end
  end
end
