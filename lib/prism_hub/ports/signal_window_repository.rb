# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    # The window of evidence assessments are recomputed from, and each source's read position.
    class SignalWindowRepository
      def cursor(source_id:)
        raise NotImplementedError
      end

      def advance_cursor(source_id:, cursor:, at:)
        raise NotImplementedError
      end

      # Idempotent on (source_id, external_id): an edited post replaces what was stored.
      def store(evidence:)
        raise NotImplementedError
      end

      # The newest `limit` items published at or after `since`, oldest first.
      def since(time:, limit:)
        raise NotImplementedError
      end

      def prune(before:)
        raise NotImplementedError
      end
    end
  end
end
