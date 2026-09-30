# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    # Runs the signal loop on an interval. A pass that fails is logged and the loop goes on: a
    # scheduler that dies leaves people without alerts and without any sign that it happened.
    class SignalScheduler
      def initialize(ingest:, interval_seconds:, logger:, clock: -> { Time.now.utc }, sleeper: ->(seconds) { sleep(seconds) })
        @ingest = ingest
        @interval_seconds = positive_number(interval_seconds)
        @logger = logger
        @clock = clock
        @sleeper = sleeper
        @stopped = false
      end

      def run_once
        result = @ingest.call(now: @clock.call.utc)
        summary = result.summary
        @logger.info(
          "signal_pass read=#{result.read} failed_sources=#{result.failed_sources.length} " \
          "alerts=#{summary.alerts} retractions=#{summary.retractions} skipped=#{summary.skipped.values.sum}"
        )
        result
      rescue StandardError => error
        @logger.error("signal_pass_failed error_class=#{error.class.name} code=#{error.respond_to?(:code) ? error.code : "none"}")
        nil
      end

      def run
        until @stopped
          run_once
          @sleeper.call(@interval_seconds) unless @stopped
        end
      end

      def stop
        @stopped = true
      end

      private

      def positive_number(value)
        number = Float(value)
        return number if number.positive?

        raise ArgumentError
      rescue ArgumentError, TypeError
        raise PrismHub::ConfigurationError.new("hub.signal.scheduler.interval.invalid", "interval seconds must be a positive number")
      end
    end
  end
end
