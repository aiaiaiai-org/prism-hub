# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    class TelegramSurfaceBinding
      STATUSES = %w[active revoked].freeze
      LOGICAL_CHANNEL_PATTERN = /\A[^[:cntrl:]]{1,100}\z/

      attr_reader :id,
        :workspace_id,
        :bot_instance_id,
        :logical_channel,
        :chat_id,
        :message_thread_id,
        :created_by_user_identity_id,
        :status,
        :revoked_at,
        :revoked_by_user_identity_id

      def initialize(
        id:,
        workspace_id:,
        bot_instance_id:,
        logical_channel:,
        chat_id:,
        created_by_user_identity_id:,
        status:,
        message_thread_id: nil,
        revoked_at: nil,
        revoked_by_user_identity_id: nil
      )
        @id = reference(id, "id")
        @workspace_id = reference(workspace_id, "workspace_id")
        @bot_instance_id = reference(bot_instance_id, "bot_instance_id")
        @logical_channel = logical_channel_value(logical_channel)
        @chat_id = integer(chat_id, "chat_id", allow_negative: true)
        @message_thread_id = optional_positive_integer(message_thread_id, "message_thread_id")
        @created_by_user_identity_id = reference(created_by_user_identity_id, "created_by_user_identity_id")
        @status = status_value(status)
        @revoked_at = timestamp(revoked_at, "revoked_at")
        @revoked_by_user_identity_id = optional_reference(
          revoked_by_user_identity_id,
          "revoked_by_user_identity_id"
        )
        validate_state!
        freeze
      end

      def active?
        status == "active"
      end

      def revoked?
        status == "revoked"
      end

      def logical_context
        {"workspace" => workspace_id, "channel" => logical_channel}.freeze
      end

      def surface_scope
        "telegram:#{chat_id}:#{message_thread_id || 'root'}".freeze
      end

      def reply_target
        target = {chat_id: chat_id}
        target[:message_thread_id] = message_thread_id if message_thread_id
        target.freeze
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze if Channel::REFERENCE_PATTERN.match?(string)

        raise InputError.new(
          "hub.telegram_surface_binding.#{field}.invalid",
          "#{field} must be a non-empty stable reference"
        )
      end

      def optional_reference(value, field)
        return nil if value.nil?

        reference(value, field)
      end

      def logical_channel_value(value)
        valid = value.is_a?(String) && LOGICAL_CHANNEL_PATTERN.match?(value) && !value.strip.empty?
        return value.strip.freeze if valid

        raise InputError.new(
          "hub.telegram_surface_binding.logical_channel.invalid",
          "logical_channel must be a nonblank logical identifier"
        )
      end

      def integer(value, field, allow_negative:)
        integer = Integer(value)
        valid = !integer.zero? && (allow_negative || integer.positive?)
        return integer if valid

        raise ArgumentError
      rescue ArgumentError, TypeError
        raise InputError.new(
          "hub.telegram_surface_binding.#{field}.invalid",
          "#{field} must be a nonzero integer"
        )
      end

      def optional_positive_integer(value, field)
        return nil if value.nil?

        integer(value, field, allow_negative: false)
      end

      def status_value(value)
        string = String(value)
        return string.freeze if STATUSES.include?(string)

        raise InputError.new(
          "hub.telegram_surface_binding.status.invalid",
          "Telegram surface binding status is invalid"
        )
      end

      def timestamp(value, field)
        return nil if value.nil?
        return value.utc.freeze if value.is_a?(Time)

        raise InputError.new(
          "hub.telegram_surface_binding.#{field}.invalid",
          "#{field} must be a Time"
        )
      end

      def validate_state!
        coherent = if active?
          revoked_at.nil? && revoked_by_user_identity_id.nil?
        else
          !revoked_at.nil? && !revoked_by_user_identity_id.nil?
        end
        return if coherent

        raise InputError.new(
          "hub.telegram_surface_binding.state.invalid",
          "Telegram surface binding status and revocation fields are inconsistent"
        )
      end
    end
  end
end
