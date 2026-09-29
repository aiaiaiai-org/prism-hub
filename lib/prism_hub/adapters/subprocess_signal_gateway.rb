# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    # Reads sources with `prism-signal-collect` and assesses them with `prism-signal-runtime`.
    #
    # Both are separate processes and neither holds state: the collector is told where to resume
    # and the runtime is handed the whole window every time. Only their stdout is trusted, and only
    # after it is checked against the contract.
    class SubprocessSignalGateway < Ports::SignalGateway
      PROTOCOL_VERSION = "prism-signal.v1".freeze
      POLICY_VERSION = "fusion.v1".freeze
      DEFAULT_TIMEOUT_SECONDS = 60
      MAX_COLLECT_BYTES = 8 * 1024 * 1024
      MAX_RUNTIME_BYTES = 16 * 1024 * 1024
      MAX_STDERR_BYTES = 65_536
      MAX_EVIDENCE = 500

      def initialize(collect_command:, runtime_command:, logger:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, runner_factory: nil)
        @collect_command = collect_command.freeze
        @runtime_command = runtime_command.freeze
        @logger = logger
        @timeout_seconds = timeout_seconds
        @runner_factory = runner_factory || method(:build_runner)
      end

      def poll(source:, after:)
        command = @collect_command + [source.kind, source.channel, "poll"]
        command += ["--after", after.to_s] unless after.nil?
        result = run(command, MAX_COLLECT_BYTES, "hub.signal.collector", "")
        Polled.new(evidence: parse_evidence(result.stdout, source))
      end

      def assess(evidence:, evaluation_time:)
        return Assessed.new(assessments: [], events: []) if evidence.empty?

        if evidence.length > MAX_EVIDENCE
          raise InputError.new("hub.signal.window.too_large", "the window holds more evidence than one request may carry")
        end

        normalized = call_runtime("normalize", {"reader" => "normalize", "evidence" => evidence})
        observations = normalized.fetch("observations")
        assessed = call_runtime(
          "assess",
          {
            "policy_version" => POLICY_VERSION,
            "evaluation_time" => evaluation_time.utc.iso8601,
            "observations" => observations
          }
        )
        Assessed.new(assessments: assessed.fetch("assessments"), events: assessed.fetch("events"))
      rescue KeyError
        raise invalid_runtime("the result is missing what the contract requires")
      end

      private

      def build_runner(**options)
        ProcessRunner.new(**options)
      end

      def call_runtime(operation, payload)
        request_id = SecureRandom.hex(8)
        source = JSON.generate(
          "protocol_version" => PROTOCOL_VERSION,
          "request_id" => request_id,
          "operation" => operation,
          "payload" => payload
        )
        result = run(@runtime_command, MAX_RUNTIME_BYTES, "hub.signal.runtime", source)
        response = JSON.parse(result.stdout)
        valid = response.is_a?(Hash) &&
          response["protocol_version"] == PROTOCOL_VERSION &&
          response["request_id"] == request_id
        raise invalid_runtime("the response is not a #{PROTOCOL_VERSION} envelope") unless valid

        if response["failure"].is_a?(Hash)
          code = response["failure"]["code"].to_s[0, 64]
          raise ExecutionUnavailableError.new(
            "hub.signal.runtime.rejected",
            "Prism Signal rejected the request",
            details: {"failure_code" => code}
          )
        end
        raise invalid_runtime("the response carries no result") unless response["result"].is_a?(Hash)

        response["result"]
      rescue JSON::ParserError
        raise invalid_runtime("the response is not JSON")
      end

      def run(command, max_stdout_bytes, prefix, input)
        runner = @runner_factory.call(
          command: command,
          environment: {},
          timeout_seconds: @timeout_seconds,
          max_stdout_bytes: max_stdout_bytes,
          max_stderr_bytes: MAX_STDERR_BYTES
        )
        result = runner.call(input)
        reject_process_failure!(result, prefix)
        result
      rescue ProcessRunner::StartError => error
        raise ExecutionUnavailableError.new(
          "#{prefix}.unavailable",
          "the process could not be started",
          details: {"system_error" => error.system_error}
        )
      end

      def reject_process_failure!(result, prefix)
        if result.timed_out
          raise ExecutionUnavailableError.new("#{prefix}.timeout", "the process did not finish within the timeout")
        end
        if result.stdout_too_large || result.stderr_too_large
          raise ExecutionUnavailableError.new("#{prefix}.too_large", "the process output exceeded its limit")
        end
        return if result.exit_status == 0

        @logger.warn("#{prefix.tr(".", "_")}_failed exit_status=#{result.exit_status.inspect}")
        raise ExecutionUnavailableError.new("#{prefix}.failed", "the process exited with an error")
      end

      # Every line is checked: a source that is not the one asked for, or evidence without an
      # identity and a time, is dropped instead of stored.
      def parse_evidence(stdout, source)
        stdout.each_line.filter_map do |line|
          next if line.strip.empty?

          item = JSON.parse(line)
          next unless item.is_a?(Hash) && item["source_id"] == source.id
          next unless item["external_id"].is_a?(String) && item["external_id"].match?(/\A[^[:cntrl:]]{1,200}\z/)
          next unless usable_time?(item["published_at"])

          item
        rescue JSON::ParserError
          nil
        end
      end

      def usable_time?(value)
        Time.iso8601(value)
        true
      rescue ArgumentError, TypeError
        false
      end

      def invalid_runtime(message)
        ExecutionUnavailableError.new("hub.signal.runtime.invalid", "Prism Signal returned an unusable response: #{message}")
      end
    end
  end
end
