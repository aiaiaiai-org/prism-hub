# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class SubprocessSignalGatewayTest < Minitest::Test
  Result = PrismHub::Adapters::ProcessRunner::Result

  class Runner
    attr_reader :inputs

    def initialize(results)
      @results = results
      @inputs = []
    end

    def call(input)
      @inputs << input
      result = @results.shift
      raise result if result.is_a?(Exception)

      result
    end
  end

  class Factory
    attr_reader :commands

    def initialize(runner)
      @runner = runner
      @commands = []
    end

    def call(**options)
      @commands << options.fetch(:command)
      @runner
    end
  end

  SOURCE = PrismHub::Domain::SignalSource.new(kind: "telegram", channel: "vanek_nikolaev")
  NOW = Time.utc(2026, 9, 30, 12, 0, 0)

  def test_the_first_poll_names_no_cursor
    factory = Factory.new(Runner.new([ok(evidence_lines(101))]))

    gateway(factory).poll(source: SOURCE, after: nil)

    assert_equal ["prism-signal-collect", "telegram", "vanek_nikolaev", "poll"], factory.commands.first
  end

  def test_a_later_poll_resumes_from_the_cursor
    factory = Factory.new(Runner.new([ok(evidence_lines(101))]))

    gateway(factory).poll(source: SOURCE, after: "100")

    assert_equal %w[prism-signal-collect telegram vanek_nikolaev poll --after 100], factory.commands.first
  end

  def test_poll_returns_evidence_and_drops_what_it_cannot_trust
    lines = [
      evidence_lines(101),
      "not json\n",
      JSON.generate("source_id" => "telegram.channel:someone_else", "external_id" => "x/1", "published_at" => NOW.iso8601) + "\n",
      JSON.generate("source_id" => SOURCE.id, "external_id" => "vanek_nikolaev/102", "published_at" => "yesterday") + "\n",
      JSON.generate("source_id" => SOURCE.id, "published_at" => NOW.iso8601) + "\n",
      "\n"
    ].join
    gateway = gateway(Factory.new(Runner.new([ok(lines)])))

    polled = gateway.poll(source: SOURCE, after: nil)

    assert_equal ["vanek_nikolaev/101"], polled.evidence.map { |item| item["external_id"] }
  end

  def test_a_failing_collector_is_unavailable_not_empty
    gateway = gateway(Factory.new(Runner.new([Result.new(stdout: "", stderr: "", exit_status: 1, timed_out: false, stdout_too_large: false, stderr_too_large: false)])))

    error = assert_raises(PrismHub::ExecutionUnavailableError) { gateway.poll(source: SOURCE, after: nil) }

    assert_equal "hub.signal.collector.failed", error.code
  end

  def test_a_collector_that_cannot_start_is_unavailable
    gateway = gateway(Factory.new(Runner.new([PrismHub::Adapters::ProcessRunner::StartError.new("Errno::ENOENT")])))

    error = assert_raises(PrismHub::ExecutionUnavailableError) { gateway.poll(source: SOURCE, after: nil) }

    assert_equal "hub.signal.collector.unavailable", error.code
  end

  def test_assess_reads_then_fuses_and_returns_the_assessments
    runner = Runner.new([runtime("normalize", "reader" => "normalize", "observations" => [{"o" => 1}], "skipped" => []),
      runtime("assess", "assessments" => [{"assessment_id" => "a"}], "events" => [{"seq" => 1}], "skipped" => [])])
    gateway = gateway(Factory.new(runner))

    assessed = gateway.assess(evidence: [{"external_id" => "x"}], evaluation_time: NOW)

    assert_equal [{"assessment_id" => "a"}], assessed.assessments
    assert_equal [{"seq" => 1}], assessed.events
    normalize, assess = runner.inputs.map { |input| JSON.parse(input) }
    assert_equal "prism-signal.v1", normalize.fetch("protocol_version")
    assert_equal "normalize", normalize.fetch("operation")
    assert_equal "normalize", normalize.dig("payload", "reader")
    assert_equal "assess", assess.fetch("operation")
    assert_equal "fusion.v1", assess.dig("payload", "policy_version")
    assert_equal "2026-09-30T12:00:00Z", assess.dig("payload", "evaluation_time")
    assert_equal [{"o" => 1}], assess.dig("payload", "observations")
  end

  def test_an_empty_window_starts_no_process
    factory = Factory.new(Runner.new([]))

    assessed = gateway(factory).assess(evidence: [], evaluation_time: NOW)

    assert_empty assessed.assessments
    assert_empty factory.commands
  end

  def test_a_rejection_carries_only_the_failure_code
    gateway = gateway(Factory.new(Runner.new([rejecting("invalid_request")])))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.assess(evidence: [{"external_id" => "x"}], evaluation_time: NOW)
    end

    assert_equal "hub.signal.runtime.rejected", error.code
    assert_equal({"failure_code" => "invalid_request"}, error.details)
  end

  def test_a_response_for_another_request_is_refused
    stale = ok(JSON.generate("protocol_version" => "prism-signal.v1", "request_id" => "someone-else", "result" => {"observations" => []}))
    gateway = gateway(Factory.new(Runner.new([stale])))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.assess(evidence: [{"external_id" => "x"}], evaluation_time: NOW)
    end

    assert_equal "hub.signal.runtime.invalid", error.code
  end

  def test_a_result_without_the_contracted_fields_is_refused
    runner = Runner.new([runtime("normalize", "reader" => "normalize", "observations" => [], "skipped" => []),
      runtime("assess", "assessments" => [])])
    gateway = gateway(Factory.new(runner))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.assess(evidence: [{"external_id" => "x"}], evaluation_time: NOW)
    end

    assert_equal "hub.signal.runtime.invalid", error.code
  end

  def test_a_source_must_be_a_telegram_username
    ["--after", "a b", "ab", "x" * 40, "1abcd", ""].each do |channel|
      assert_raises(PrismHub::ConfigurationError) { PrismHub::Domain::SignalSource.new(kind: "telegram", channel: channel) }
    end
    assert_raises(PrismHub::ConfigurationError) { PrismHub::Domain::SignalSource.new(kind: "rss", channel: "vanek_nikolaev") }
    assert_equal "telegram.channel:vanek_nikolaev", SOURCE.id
  end

  private

  def gateway(factory)
    runner = factory.instance_variable_get(:@runner)
    runner.extend(EchoRequestId)
    PrismHub::Adapters::SubprocessSignalGateway.new(
      collect_command: ["prism-signal-collect"],
      runtime_command: ["prism-signal-runtime", "--json"],
      logger: Logger.new(File::NULL),
      runner_factory: factory
    )
  end

  # The runtime echoes the request_id it was given; the gateway generates it, so a fake answers
  # from the request it receives.
  module EchoRequestId
    def call(input)
      request = begin
        JSON.parse(input)
      rescue JSON::ParserError
        nil
      end
      @inputs << input
      result = @results.shift
      raise result if result.is_a?(Exception)
      return result unless result.respond_to?(:call)

      result.call(request)
    end
  end

  def ok(stdout)
    Result.new(stdout: stdout, stderr: "", exit_status: 0, timed_out: false, stdout_too_large: false, stderr_too_large: false)
  end

  def runtime(_operation, result)
    lambda do |request|
      ok(JSON.generate("protocol_version" => "prism-signal.v1", "request_id" => request.fetch("request_id"), "result" => result))
    end
  end

  def rejecting(code)
    lambda do |request|
      ok(JSON.generate("protocol_version" => "prism-signal.v1", "request_id" => request.fetch("request_id"), "failure" => {"code" => code, "message" => "text"}))
    end
  end

  def evidence_lines(id)
    JSON.generate(
      "source_id" => SOURCE.id,
      "external_id" => "vanek_nikolaev/#{id}",
      "published_at" => NOW.iso8601,
      "text" => "шахеди на Київ"
    ) + "\n"
  end
end
