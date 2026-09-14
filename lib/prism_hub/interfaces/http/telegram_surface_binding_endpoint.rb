# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Interfaces
    module Http
      class TelegramSurfaceBindingEndpoint
        REQUIRED_FIELDS = %w[workspace_id bot_instance_id logical_channel chat_id provider provider_scope subject_id].freeze
        OPTIONAL_FIELDS = %w[message_thread_id].freeze

        def initialize(bind_telegram_surface:, request_body:)
          @bind_telegram_surface = bind_telegram_surface
          @request_body = request_body
        end

        def call(request, authorisation_context:)
          payload = @request_body.parse(request)
          validate!(payload)

          binding = @bind_telegram_surface.call(
            authorisation_context: authorisation_context,
            workspace_id: payload.fetch("workspace_id"),
            bot_instance_id: payload.fetch("bot_instance_id"),
            logical_channel: payload.fetch("logical_channel"),
            chat_id: payload.fetch("chat_id"),
            message_thread_id: payload["message_thread_id"],
            provider: payload.fetch("provider"),
            provider_scope: payload.fetch("provider_scope"),
            subject_id: payload.fetch("subject_id")
          )

          JsonResponse.call(200, {"binding" => serialize(binding)})
        end

        private

        def validate!(payload)
          unless payload.is_a?(Hash)
            raise InputError.new("hub.telegram_surface_binding.request.invalid", "Telegram surface binding request must be a JSON object")
          end

          allowed = REQUIRED_FIELDS + OPTIONAL_FIELDS
          unless (payload.keys - allowed).empty? && (REQUIRED_FIELDS - payload.keys).empty?
            raise InputError.new("hub.telegram_surface_binding.request.invalid", "Telegram surface binding request contains unsupported or missing fields")
          end

          strings = %w[workspace_id bot_instance_id logical_channel provider provider_scope subject_id]
          unless strings.all? { |field| payload[field].is_a?(String) && !payload[field].empty? }
            raise InputError.new("hub.telegram_surface_binding.request.invalid", "Telegram surface binding identifiers must be non-empty strings")
          end

          unless payload["chat_id"].is_a?(Integer)
            raise InputError.new("hub.telegram_surface_binding.request.invalid", "chat_id must be an integer")
          end

          thread = payload["message_thread_id"]
          unless thread.nil? || (thread.is_a?(Integer) && thread.positive?)
            raise InputError.new("hub.telegram_surface_binding.request.invalid", "message_thread_id must be a positive integer or null")
          end
        end

        def serialize(binding)
          {
            "id" => binding.id,
            "workspace_id" => binding.workspace_id,
            "bot_instance_id" => binding.bot_instance_id,
            "logical_channel" => binding.logical_channel,
            "chat_id" => binding.chat_id,
            "message_thread_id" => binding.message_thread_id,
            "status" => binding.status
          }
        end
      end
    end
  end
end
