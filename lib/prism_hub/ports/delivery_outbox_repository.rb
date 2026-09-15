# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class DeliveryOutboxRepository
      def enqueue(request:, available_at:)
        raise NotImplementedError
      end

      def claim_due(limit:, now:, lease_seconds:)
        raise NotImplementedError
      end

      def mark_delivered(id:, lock_token:, delivered_at:)
        raise NotImplementedError
      end

      def mark_failed(id:, lock_token:, failed_at:, retry_at: nil, error_code: nil, error_details: nil)
        raise NotImplementedError
      end
    end
  end
end
