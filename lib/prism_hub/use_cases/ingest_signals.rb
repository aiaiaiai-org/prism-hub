# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    # One pass of the signal loop: read every source from where it was left, keep the window,
    # assess it, and hand the result to the fan-out.
    #
    # A source that cannot be read does not stop the pass: what the others said, and what the
    # window already holds, still decide expiries and retractions. The failure is logged.
    class IngestSignals
      Result = Struct.new(:read, :failed_sources, :summary, keyword_init: true)
      MAX_EVIDENCE = 500

      def initialize(sources:, gateway:, window_repository:, threat_registry:, ledger:, fan_out:, logger:,
        window_seconds: 21_600, ledger_retention_seconds: 86_400)
        @sources = sources
        @gateway = gateway
        @window = window_repository
        @threat_registry = threat_registry
        @ledger = ledger
        @fan_out = fan_out
        @logger = logger
        @window_seconds = window_seconds
        @ledger_retention_seconds = ledger_retention_seconds
      end

      def call(now:)
        read = 0
        failed = []
        @sources.each do |source|
          read += ingest(source, now)
        rescue ExecutionUnavailableError, InputError => error
          @logger.warn("signal_source_failed source=#{source.id} code=#{error.code}")
          failed << source.id
        end

        since = now - @window_seconds
        @window.prune(before: since)
        assessed = @gateway.assess(evidence: balanced_evidence(since), evaluation_time: now)
        # Register first: a send must refer to an incident we can later audit.
        @threat_registry.sync(assessments: assessed.assessments, now: now)
        summary = @fan_out.call(
          assessments: assessed.assessments, events: assessed.events, tracks: Array(assessed.tracks), now: now
        )
        @ledger.prune(before: now - @ledger_retention_seconds)
        Result.new(read: read, failed_sources: failed, summary: summary)
      end

      private

      # A busy channel must not crowd out quieter configured channels in the shared window.
      # Bound the total input to MAX_EVIDENCE while giving each source the same budget.
      # A source with no recent posts contributes nothing; no other channel can borrow its
      # allocation and become a de-facto priority source.
      def balanced_evidence(since)
        per_source = [MAX_EVIDENCE / @sources.length, 1].max
        @sources
          .flat_map { |source| @window.since(time: since, limit: per_source, source_id: source.id) }
          .sort_by { |item| [item.fetch("published_at"), item.fetch("source_id"), item.fetch("external_id")] }
      end

      def ingest(source, now)
        after = @window.cursor(source_id: source.id)
        polled = @gateway.poll(source: source, after: after)
        return 0 if polled.evidence.empty?

        @window.store(evidence: polled.evidence)
        newest = polled.evidence.filter_map { |item| item["external_id"][/(\d+)\z/, 1]&.to_i }.max
        @window.advance_cursor(source_id: source.id, cursor: newest.to_s, at: now) if newest && newest > after.to_i
        polled.evidence.length
      end
    end
  end
end
