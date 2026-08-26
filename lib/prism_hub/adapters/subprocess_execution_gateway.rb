# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class SubprocessExecutionGateway < Ports::ExecutionGateway
      PROTOCOL_VERSION = "prism-execution.v1"

      def initialize(runner:, logger:)
        @runner = runner
        @logger = logger
      end

      def execute(envelope)
        result = @runner.call("#{JSON.generate(envelope)}\n")
        reject_process_failure!(result)
        response = parse_response(result.stdout)
        validate_response!(response, envelope.fetch("request_id"))
        response
      end

      private

      def reject_process_failure!(result)
        if result.timed_out
          raise ExecutionUnavailableError.new(
            "hub.prism.process.timeout",
            "Prism runtime did not finish within the configured timeout"
          )
        end
        if result.stdout_too_large
          raise ExecutionUnavailableError.new(
            "hub.prism.response.too_large",
            "Prism runtime response exceeded the configured limit"
          )
        end
        return if result.exit_status == 0

        @logger.warn("prism_runtime_failed exit_status=#{result.exit_status.inspect}")
        raise ExecutionUnavailableError.new(
          "hub.prism.process.failed",
          "Prism runtime exited without a valid response"
        )
      end

      def parse_response(source)
        JSON.parse(source)
      rescue JSON::ParserError
        raise ExecutionUnavailableError.new(
          "hub.prism.response.invalid_json",
          "Prism runtime returned an invalid response envelope"
        )
      end

      def validate_response!(response, request_id)
        valid = response.is_a?(Hash) &&
          response["protocol_version"] == PROTOCOL_VERSION &&
          response["request_id"] == request_id &&
          %w[ok error].include?(response["status"])
        valid &&= response["result"].is_a?(Hash) if response["status"] == "ok"
        valid &&= response["error"].is_a?(Hash) if response["status"] == "error"
        return if valid

        raise ExecutionUnavailableError.new(
          "hub.prism.response.invalid_envelope",
          "Prism runtime response did not preserve the execution contract"
        )
      end
    end
  end
end
