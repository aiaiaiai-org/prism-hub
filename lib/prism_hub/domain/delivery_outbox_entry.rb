# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    class DeliveryOutboxEntry
      STATUSES = %w[pending processing delivered failed].freeze
      IDEMPOTENCY_KEY_PATTERN = /\A[0-9a-f]{64}\z/

      attr_reader :id, :workspace, :channel, :idempotency_key, :intent_payload,
        :status, :attempts, :available_at, :locked_at, :lock_token,
        :delivered_at, :failed_at, :last_error_code, :last_error_details

      def initialize(
        id:, workspace:, channel:, idempotency_key:, intent_payload:, status:, attempts:,
        available_at:, locked_at: nil, lock_token: nil, delivered_at: nil, failed_at: nil,
        last_error_code: nil, last_error_details: nil
      )
        @id = reference(id, "id")
        @workspace = logical_identifier(workspace, "workspace")
        @channel = logical_identifier(channel, "channel")
        @idempotency_key = idempotency_key_value(idempotency_key)
        @intent_payload = payload(intent_payload)
        @status = status_value(status)
        @attempts = attempts_value(attempts)
        @available_at = timestamp(available_at, "available_at")
        @locked_at = timestamp(locked_at, "locked_at")
        @lock_token = optional_token(lock_token)
        @delivered_at = timestamp(delivered_at, "delivered_at")
        @failed_at = timestamp(failed_at, "failed_at")
        @last_error_code = optional_string(last_error_code, "last_error_code", 160)
        @last_error_details = optional_hash(last_error_details, "last_error_details")
        validate_state!
        freeze
      end

      def processing?
        status == "processing"
      end

      def due?(now:)
        return false unless status == "pending"
        available_at <= timestamp(now, "now")
      end

      def to_h
        {
          "id" => id,
          "workspace" => workspace,
          "channel" => channel,
          "idempotency_key" => idempotency_key,
          "intent_payload" => intent_payload,
          "status" => status,
          "attempts" => attempts,
          "available_at" => available_at.iso8601,
          "locked_at" => locked_at&.iso8601,
          "lock_token" => lock_token,
          "delivered_at" => delivered_at&.iso8601,
          "failed_at" => failed_at&.iso8601,
          "last_error_code" => last_error_code,
          "last_error_details" => last_error_details
        }.freeze
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze if Channel::REFERENCE_PATTERN.match?(string)
        raise InputError.new("hub.delivery_outbox.#{field}.invalid", "#{field} is invalid")
      end

      def logical_identifier(value, field)
        valid = value.is_a?(String) && value.match?(/\A[^[:cntrl:]]{1,100}\z/) && !value.strip.empty?
        return value.strip.freeze if valid
        raise InputError.new("hub.delivery_outbox.#{field}.invalid", "#{field} must be a nonblank logical identifier")
      end

      def idempotency_key_value(value)
        return value.dup.freeze if value.is_a?(String) && value.match?(IDEMPOTENCY_KEY_PATTERN)
        raise InputError.new("hub.delivery_outbox.idempotency_key.invalid", "idempotency key is invalid")
      end

      def payload(value)
        unless value.is_a?(Hash) && value.keys.include?("schema_version")
          raise InputError.new("hub.delivery_outbox.intent_payload.invalid", "intent payload must be a versioned object")
        end
        DeepFreeze.call(Marshal.load(Marshal.dump(value)))
      rescue TypeError
        raise InputError.new("hub.delivery_outbox.intent_payload.invalid", "intent payload is not serializable")
      end

      def status_value(value)
        string = String(value)
        return string.freeze if STATUSES.include?(string)
        raise InputError.new("hub.delivery_outbox.status.invalid", "outbox status is invalid")
      end

      def attempts_value(value)
        integer = Integer(value)
        return integer if integer >= 0
        raise ArgumentError
      rescue ArgumentError, TypeError
        raise InputError.new("hub.delivery_outbox.attempts.invalid", "attempts must be nonnegative")
      end

      def timestamp(value, field)
        return nil if value.nil?
        return value.utc.freeze if value.is_a?(Time)
        raise InputError.new("hub.delivery_outbox.#{field}.invalid", "#{field} must be a Time")
      end

      def optional_token(value)
        return nil if value.nil?
        string = String(value)
        return string.freeze if string.match?(/\A[0-9a-f]{64}\z/)
        raise InputError.new("hub.delivery_outbox.lock_token.invalid", "lock token is invalid")
      end

      def optional_string(value, field, limit)
        return nil if value.nil?
        string = String(value)
        return string.freeze if !string.empty? && string.length <= limit && !string.match?(/[[:cntrl:]]/)
        raise InputError.new("hub.delivery_outbox.#{field}.invalid", "#{field} is invalid")
      end

      def optional_hash(value, field)
        return nil if value.nil?
        return DeepFreeze.call(Marshal.load(Marshal.dump(value))) if value.is_a?(Hash)
        raise InputError.new("hub.delivery_outbox.#{field}.invalid", "#{field} must be an object")
      end

      def validate_state!
        valid = if processing?
          !locked_at.nil? && !lock_token.nil?
        else
          locked_at.nil? && lock_token.nil?
        end
        valid &&= delivered_at.nil? || status == "delivered"
        return if valid
        raise InputError.new("hub.delivery_outbox.state.invalid", "outbox status and lock/delivery fields are inconsistent")
      end
    end
  end
end
