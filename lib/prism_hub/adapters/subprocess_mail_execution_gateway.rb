# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class SubprocessMailExecutionGateway < Ports::MailExecutionGateway
      SCHEMA_VERSION = "prism-mail.digest.v1"
      MODE = "extractive"
      DEFAULT_TIMEOUT_SECONDS = 30
      MAX_STDOUT_BYTES = 1_048_576
      MAX_STDERR_BYTES = 65_536

      def initialize(command:, origin:, logger:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, runner_factory: nil)
        @command = command.freeze
        @origin = origin
        @logger = logger
        @timeout_seconds = timeout_seconds
        @runner_factory = runner_factory || method(:build_runner)
      end

      def execute(mailbox_id:, since:, before:, access_token:)
        expected = {
          "mailbox_id" => mailbox_id,
          "window" => {"since" => since, "before" => before}
        }
        runner = @runner_factory.call(
          command: @command,
          environment: worker_environment(
            mailbox_id: mailbox_id,
            since: since,
            before: before,
            access_token: access_token
          ),
          timeout_seconds: @timeout_seconds,
          max_stdout_bytes: MAX_STDOUT_BYTES,
          max_stderr_bytes: MAX_STDERR_BYTES
        )
        result = runner.call("")
        reject_process_failure!(result)
        artifact = parse_artifact(result.stdout)
        validate_artifact!(artifact, expected)
        artifact
      rescue ProcessRunner::StartError => error
        raise ExecutionUnavailableError.new(
          "hub.mail.process.unavailable",
          "Prism Mail worker process could not be started",
          details: {"system_error" => error.system_error}
        )
      end

      private

      def build_runner(**options)
        ProcessRunner.new(**options)
      end

      def worker_environment(mailbox_id:, since:, before:, access_token:)
        {
          "HQBASE_ORIGIN" => @origin,
          "HQBASE_ACCESS_TOKEN" => access_token,
          "PRISM_MAIL_MAILBOX_ID" => mailbox_id,
          "PRISM_MAIL_SINCE" => since,
          "PRISM_MAIL_BEFORE" => before
        }.freeze
      end

      def reject_process_failure!(result)
        if result.timed_out
          raise ExecutionUnavailableError.new(
            "hub.mail.process.timeout",
            "Prism Mail worker did not finish within the configured timeout"
          )
        end
        if result.stdout_too_large
          raise ExecutionUnavailableError.new(
            "hub.mail.response.too_large",
            "Prism Mail worker response exceeded the configured limit"
          )
        end
        return if result.exit_status == 0

        @logger.warn("prism_mail_worker_failed exit_status=#{result.exit_status.inspect}")
        raise ExecutionUnavailableError.new(
          "hub.mail.process.failed",
          "Prism Mail worker exited without a valid digest artifact"
        )
      end

      def parse_artifact(source)
        JSON.parse(source)
      rescue JSON::ParserError
        raise ExecutionUnavailableError.new(
          "hub.mail.response.invalid_json",
          "Prism Mail worker returned invalid JSON"
        )
      end

      def validate_artifact!(artifact, expected)
        valid = artifact.is_a?(Hash) &&
          artifact["schema_version"] == SCHEMA_VERSION &&
          artifact["mode"] == MODE &&
          artifact["mailbox_id"] == expected.fetch("mailbox_id") &&
          artifact["window"] == expected.fetch("window") &&
          valid_counts?(artifact) &&
          valid_entries?(artifact)
        return if valid

        raise ExecutionUnavailableError.new(
          "hub.mail.response.invalid_artifact",
          "Prism Mail worker response did not preserve the digest contract"
        )
      end

      def valid_counts?(artifact)
        counts = %w[matched_count selected_count omitted_count].map { |key| artifact[key] }
        return false unless counts.all? { |value| value.is_a?(Integer) && value >= 0 }

        matched, selected, omitted = counts
        matched == selected + omitted
      end

      def valid_entries?(artifact)
        entries = artifact["entries"]
        return false unless entries.is_a?(Array) && entries.length == artifact["selected_count"]

        entries.all? do |entry|
          entry.is_a?(Hash) && entry["kind"] == "source_excerpt" && entry["evidence"].is_a?(Hash)
        end
      end
    end
  end
end
