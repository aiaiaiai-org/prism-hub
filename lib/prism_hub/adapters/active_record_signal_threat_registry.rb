# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    # Registers source-reported threat episodes, never people or exact coordinates.
    # The assessment_id is the idempotency key; the database UUID is the durable threat_id.
    class ActiveRecordSignalThreatRegistry < Ports::SignalThreatRegistry
      CLASSES = %w[drone bomb missile].freeze
      STATUSES = %w[active expired retracted].freeze

      def sync(assessments:, now:)
        raise ArgumentError, "now must be a Time" unless now.is_a?(Time)

        registered = 0
        assessments.each do |assessment|
          data = attributes(assessment)
          ::ActiveRecord::Base.transaction do
            record = ActiveRecordRecords::SignalThreatRecord
              .create_or_find_by!(assessment_id: data.fetch(:assessment_id)) do |new_record|
                new_record.assign_attributes(data.merge(
                  first_reported_at: data.fetch(:first_reported_at),
                  last_evaluated_at: now,
                  created_at: now,
                  updated_at: now
                ))
              end
            record.lock!
            # A stale assessment pass never reopens a terminal incident.
            next if record.last_evaluated_at > now
            next if record.status != "active" && data.fetch(:status) == "active"

            existing_reports = Array(record.source_reports)
            combined_reports = (existing_reports + data.fetch(:source_reports))
              .uniq { |report| [report.fetch("source_id"), report.fetch("evidence_id")] }
              .sort_by { |report| [report.fetch("observed_at"), report.fetch("source_id"), report.fetch("evidence_id")] }
            record.update!(
              data.merge(
                first_reported_at: [record.first_reported_at, data.fetch(:first_reported_at)].min,
                last_reported_at: [record.last_reported_at, data.fetch(:last_reported_at)].max,
                last_evaluated_at: now,
                source_reports: combined_reports,
                updated_at: now
              )
            )
            registered += 1
          end
        end

        # A missing assessment is never an all-clear. It may expire by time only.
        ActiveRecordRecords::SignalThreatRecord
          .where(status: "active")
          .where("valid_until <= ?", now)
          .update_all(status: "expired", last_evaluated_at: now, updated_at: now)
        registered
      end

      private

      def attributes(value)
        id = value.fetch("assessment_id")
        hazard_class = value.fetch("class")
        status = value.fetch("status")
        kinds = value.fetch("kinds")
        raise ArgumentError, "invalid threat identifier" unless id.is_a?(String) && id.length.between?(1, 200)
        raise ArgumentError, "invalid hazard class" unless CLASSES.include?(hazard_class)
        raise ArgumentError, "invalid threat status" unless STATUSES.include?(status)
        raise ArgumentError, "invalid hazard kinds" unless kinds.is_a?(Array) && kinds.all? { |kind| kind.is_a?(String) }

        place = value["place"]
        raise ArgumentError, "invalid named destination" unless place.nil? ||
          (place.is_a?(Hash) && (place.keys - %w[id name]).empty?)
        destination_id = place && place["id"]
        destination_name = place && place["name"]
        raise ArgumentError, "invalid destination id" unless destination_id.nil? ||
          (destination_id.is_a?(String) && destination_id.length <= 200)
        raise ArgumentError, "invalid destination name" unless destination_name.nil? ||
          (destination_name.is_a?(String) && destination_name.length <= 200)

        from = timestamp(value.fetch("valid_from"))
        evidence = value.fetch("evidence")
        raise ArgumentError, "evidence must be an array" unless evidence.is_a?(Array)

        reports = evidence.map do |item|
          {
            "source_id" => item.fetch("source_id"),
            "evidence_id" => item.fetch("evidence_id"),
            "url" => item.fetch("url"),
            "observed_at" => timestamp(item.fetch("observed_at")).iso8601
          }
        end
        # A missing field means the producer predates source-status support.
        # In particular, never conflate "unknown" (nil) with "none live" ([]).
        # Each active ID is one channel identity, not a verified independent report.
        live_sources = nil
        if value.key?("active_sources")
          live_sources = value.fetch("active_sources")
          raise ArgumentError, "active_sources must be an array" unless live_sources.is_a?(Array)
          unless live_sources.all? { |source| source.is_a?(String) && source.match?(/\A[a-z0-9_.-]+:[a-z0-9_.-]+\z/) }
            raise ArgumentError, "invalid active source identifier"
          end
          unless (live_sources - reports.map { |report| report.fetch("source_id") }).empty?
            raise ArgumentError, "active source without evidence"
          end
          if (status == "active" && live_sources.empty?) || (status != "active" && live_sources.any?)
            raise ArgumentError, "active sources disagree with status"
          end
        end

        data = {
          assessment_id: id,
          hazard_class: hazard_class,
          hazard_kinds: kinds.uniq.sort,
          destination_id: destination_id,
          destination_name: destination_name,
          status: status,
          first_reported_at: from,
          last_reported_at: ([from] + reports.map { |report| timestamp(report.fetch("observed_at")) }).max,
          valid_until: timestamp(value.fetch("valid_until")),
          source_reports: reports
          # The arrival window intentionally stays NULL: no ETA is inferred from text,
          # coordinates, or TTL. Only an explicitly sourced future contract may set it.
        }
        data[:active_sources] = live_sources.uniq.sort unless live_sources.nil?
        data
      end

      def timestamp(text)
        raise ArgumentError, "invalid report timestamp" unless text.is_a?(String)

        Time.iso8601(text).utc
      end
    end
  end
end
