# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class ProcessDeliveryOutbox
      DEFAULT_RETRY_SECONDS = 30
      DEFAULT_RATE_LIMIT_RETRY_SECONDS = 60

      def initialize(outbox_repository:, dispatch_delivery:, clock: -> { Time.now.utc }, retry_seconds: DEFAULT_RETRY_SECONDS, rate_limit_retry_seconds: DEFAULT_RATE_LIMIT_RETRY_SECONDS)
        @outbox_repository = outbox_repository
        @dispatch_delivery = dispatch_delivery
        @clock = clock
        @retry_seconds = positive_integer(retry_seconds, "retry_seconds")
        @rate_limit_retry_seconds = positive_integer(rate_limit_retry_seconds, "rate_limit_retry_seconds")
      end

      def call(limit:, lease_seconds:)
        now = @clock.call.utc
        entries = @outbox_repository.claim_due(limit: limit, now: now, lease_seconds: lease_seconds)
        entries.map { |entry| process(entry) }.freeze
      end

      private

      def process(entry)
        request = Domain::DeliveryRequest.from_h(entry.intent_payload)
        @dispatch_delivery.call(request: request)
        @outbox_repository.mark_delivered(
          id: entry.id,
          lock_token: entry.lock_token,
          delivered_at: @clock.call.utc
        )
      rescue ExecutionUnavailableError => error
        @outbox_repository.mark_failed(
          id: entry.id,
          lock_token: entry.lock_token,
          failed_at: @clock.call.utc,
          retry_at: @clock.call.utc + retry_delay(error),
          error_code: error.code,
          error_details: error.details
        )
      rescue Error => error
        @outbox_repository.mark_failed(
          id: entry.id,
          lock_token: entry.lock_token,
          failed_at: @clock.call.utc,
          error_code: error.code,
          error_details: error.details
        )
      rescue StandardError => error
        @outbox_repository.mark_failed(
          id: entry.id,
          lock_token: entry.lock_token,
          failed_at: @clock.call.utc,
          error_code: "hub.delivery.worker.unexpected",
          error_details: {"cause" => error.class.name}
        )
      end

      def retry_delay(error)
        return @retry_seconds unless error.code == "hub.bot.delivery.rate_limited"
        value = error.details&.fetch("retry_after_seconds", nil)
        seconds = Integer(value)
        return seconds if seconds.positive?
        @rate_limit_retry_seconds
      rescue ArgumentError, TypeError
        @rate_limit_retry_seconds
      end

      def positive_integer(value, field)
        integer = Integer(value)
        return integer if integer.positive?
        raise ArgumentError, "#{field} must be positive"
      rescue ArgumentError, TypeError
        raise ConfigurationError.new("hub.delivery.worker.#{field}.invalid", "#{field} must be a positive integer")
      end
    end
  end
end
