# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordSignalWindowRepository < Ports::SignalWindowRepository
      def cursor(source_id:)
        ActiveRecordRecords::SignalSourceCursor.find_by(source_id: source_id)&.cursor
      end

      def advance_cursor(source_id:, cursor:, at:)
        record = ActiveRecordRecords::SignalSourceCursor.find_or_initialize_by(source_id: source_id)
        record.update!(cursor: cursor, updated_at: at)
      rescue ::ActiveRecord::RecordNotUnique
        retry
      end

      def store(evidence:)
        evidence.each do |item|
          source_id = item.fetch("source_id")
          external_id = item.fetch("external_id")
          record = ActiveRecordRecords::SignalEvidence.find_or_initialize_by(
            source_id: source_id,
            external_id: external_id
          )
          record.update!(published_at: Time.iso8601(item.fetch("published_at")).utc, payload: item)
        rescue ::ActiveRecord::RecordNotUnique
          retry
        end
        evidence.length
      end

      def since(time:, limit:)
        ActiveRecordRecords::SignalEvidence
          .where("published_at >= ?", time)
          .order(published_at: :desc, external_id: :desc)
          .limit(limit)
          .map(&:payload)
          .reverse
      end

      def prune(before:)
        ActiveRecordRecords::SignalEvidence.where("published_at < ?", before).delete_all
      end
    end
  end
end
