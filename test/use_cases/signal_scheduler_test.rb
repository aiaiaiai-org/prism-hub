# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class SignalSchedulerTest < Minitest::Test
  NOW = Time.utc(2026, 9, 30, 12, 0, 0)
  Summary = Struct.new(:alerts, :retractions, :skipped, keyword_init: true)
  Result = Struct.new(:read, :failed_sources, :summary, keyword_init: true)

  class Ingest
    attr_reader :calls

    def initialize(outcomes)
      @outcomes = outcomes
      @calls = []
    end

    def call(now:)
      @calls << now
      outcome = @outcomes.shift
      raise outcome if outcome.is_a?(Exception)

      outcome || Result.new(read: 0, failed_sources: [], summary: Summary.new(alerts: 0, retractions: 0, skipped: {}))
    end
  end

  def test_a_pass_runs_at_the_clock_time
    ingest = Ingest.new([])

    scheduler(ingest).run_once

    assert_equal [NOW], ingest.calls
  end

  def test_a_failed_pass_is_logged_and_does_not_stop_the_loop
    ingest = Ingest.new([PrismHub::ExecutionUnavailableError.new("hub.signal.runtime.timeout", "slow"), nil])
    log = StringIO.new
    scheduler = scheduler(ingest, log: log)

    assert_nil scheduler.run_once
    refute_nil scheduler.run_once
    assert_includes log.string, "signal_pass_failed error_class=PrismHub::ExecutionUnavailableError code=hub.signal.runtime.timeout"
    assert_equal 2, ingest.calls.length
  end

  def test_the_loop_sleeps_between_passes_until_stopped
    ingest = Ingest.new([])
    sleeps = []
    holder = []
    sleeper = lambda do |seconds|
      sleeps << seconds
      holder.first.stop if sleeps.length == 3
    end
    scheduler = scheduler(ingest, sleeper: sleeper)
    holder << scheduler

    scheduler.run

    assert_equal [60.0, 60.0, 60.0], sleeps
    assert_equal 3, ingest.calls.length
  end

  def test_the_interval_must_be_positive
    [0, -1, "x", nil].each do |value|
      assert_raises(PrismHub::ConfigurationError) do
        PrismHub::UseCases::SignalScheduler.new(ingest: Ingest.new([]), interval_seconds: value, logger: Logger.new(File::NULL))
      end
    end
  end

  private

  def scheduler(ingest, log: StringIO.new, sleeper: ->(_) { })
    PrismHub::UseCases::SignalScheduler.new(
      ingest: ingest,
      interval_seconds: 60,
      logger: Logger.new(log),
      clock: -> { NOW },
      sleeper: sleeper
    )
  end
end
