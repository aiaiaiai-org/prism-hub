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

      def initialize(sources:, gateway:, window_repository:, ledger:, fan_out:, logger:,
        window_seconds: 14_400, ledger_retention_seconds: 86_400)
        @sources = sources
        @gateway = gateway
        @window = window_repository
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
        assessed = @gateway.assess(evidence: @window.since(time: since, limit: MAX_EVIDENCE), evaluation_time: now)
        summary = @fan_out.call(assessments: assessed.assessments, events: assessed.events, now: now)
        @ledger.prune(before: now - @ledger_retention_seconds)
        Result.new(read: read, failed_sources: failed, summary: summary)
      end

      private

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
