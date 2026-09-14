# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class ActiveRecordDeliveryOutboxRepository < Ports::DeliveryOutboxRepository
      STATUS_PENDING = "pending".freeze
      STATUS_PROCESSING = "processing".freeze
      STATUS_DELIVERED = "delivered".freeze
      STATUS_FAILED = "failed".freeze

      def enqueue(request:, available_at:)
        validate_request!(request)
        timestamp = normalized_time(available_at, "available_at")
        record = ActiveRecordRecords::DeliveryOutboxEntry.create!(
          workspace: request.workspace,
          logical_channel: request.channel,
          idempotency_key: request.idempotency_key,
          intent_payload: request.to_h,
          status: STATUS_PENDING,
          attempts: 0,
          available_at: timestamp
        )
        to_domain(record)
      rescue ::ActiveRecord::RecordNotUnique
        existing = ActiveRecordRecords::DeliveryOutboxEntry.find_by!(idempotency_key: request.idempotency_key)
        to_domain(existing)
      end

      def claim_due(limit:, now:, lease_seconds:)
        batch_size = positive_integer(limit, "limit")
        timestamp = normalized_time(now, "now")
        lease = positive_integer(lease_seconds, "lease_seconds")
        lock_cutoff = timestamp - lease
        records = []

        ::ActiveRecord::Base.transaction do
          scope = ActiveRecordRecords::DeliveryOutboxEntry
            .where("(status = ? AND available_at <= ?) OR (status = ? AND locked_at <= ?)", STATUS_PENDING, timestamp, STATUS_PROCESSING, lock_cutoff)
            .order(:available_at, :created_at)
            .limit(batch_size)
            .lock("FOR UPDATE SKIP LOCKED")

          scope.to_a.each do |record|
            token = SecureRandom.hex(32)
            record.update!(
              status: STATUS_PROCESSING,
              attempts: record.attempts + 1,
              locked_at: timestamp,
              lock_token: token,
              failed_at: nil
            )
            records << to_domain(record)
          end
        end

        records
      end

      def mark_delivered(id:, lock_token:, delivered_at:)
        ::ActiveRecord::Base.transaction do
          record = locked_record!(id, lock_token)
          record.update!(
            status: STATUS_DELIVERED,
            locked_at: nil,
            lock_token: nil,
            delivered_at: normalized_time(delivered_at, "delivered_at")
          )
          to_domain(record)
        end
      end

      def mark_failed(id:, lock_token:, failed_at:, retry_at: nil, error_code: nil, error_details: nil)
        ::ActiveRecord::Base.transaction do
          record = locked_record!(id, lock_token)
          failed = normalized_time(failed_at, "failed_at")
          retry_timestamp = retry_at.nil? ? nil : normalized_time(retry_at, "retry_at")
          record.update!(
            status: retry_timestamp ? STATUS_PENDING : STATUS_FAILED,
            available_at: retry_timestamp || record.available_at,
            locked_at: nil,
            lock_token: nil,
            failed_at: failed,
            last_error_code: error_code,
            last_error_details: error_details
          )
          to_domain(record)
        end
      end

      private

      def validate_request!(request)
        return if request.is_a?(Domain::DeliveryRequest)
        raise InputError.new("hub.delivery_outbox.request.invalid", "outbox enqueue requires a DeliveryRequest")
      end

      def locked_record!(id, lock_token)
        reference = String(id)
        token = String(lock_token)
        record = ActiveRecordRecords::DeliveryOutboxEntry.lock.find_by(id: reference, lock_token: token, status: STATUS_PROCESSING)
        return record if record
        raise InputError.new("hub.delivery_outbox.lock.invalid", "outbox lock is no longer valid")
      end

      def positive_integer(value, field)
        integer = Integer(value)
        return integer if integer.positive?
        raise ArgumentError
      rescue ArgumentError, TypeError
        raise InputError.new("hub.delivery_outbox.#{field}.invalid", "#{field} must be positive")
      end

      def normalized_time(value, field)
        return value.utc if value.is_a?(Time)
        raise InputError.new("hub.delivery_outbox.#{field}.invalid", "#{field} must be a Time")
      end

      def to_domain(record)
        Domain::DeliveryOutboxEntry.new(
          id: record.id,
          workspace: record.workspace,
          channel: record.logical_channel,
          idempotency_key: record.idempotency_key,
          intent_payload: record.intent_payload,
          status: record.status,
          attempts: record.attempts,
          available_at: record.available_at.to_time.utc,
          locked_at: record.locked_at&.to_time&.utc,
          lock_token: record.lock_token,
          delivered_at: record.delivered_at&.to_time&.utc,
          failed_at: record.failed_at&.to_time&.utc,
          last_error_code: record.last_error_code,
          last_error_details: record.last_error_details
        )
      end
    end
  end
end
