# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class SubprocessMailExecutionGatewayTest < Minitest::Test
  Result = PrismHub::Adapters::ProcessRunner::Result

  class FakeRunner
    attr_reader :input

    def initialize(result: nil, error: nil)
      @result = result
      @error = error
    end

    def call(input)
      @input = input
      raise @error if @error

      @result
    end
  end

  class CapturingFactory
    attr_reader :options

    def initialize(runner)
      @runner = runner
    end

    def call(**options)
      @options = options
      @runner
    end
  end

  def test_passes_mail_access_only_through_the_worker_environment
    runner = FakeRunner.new(result: success_result(valid_artifact))
    factory = CapturingFactory.new(runner)
    gateway = gateway_for(runner_factory: factory)

    response = gateway.execute(**request, access_token: "secret-token")

    assert_equal valid_artifact, response
    assert_equal "", runner.input
    assert_equal ["prism-mail"], factory.options.fetch(:command)
    assert_equal "https://mail.example.test", factory.options.fetch(:environment).fetch("HQBASE_ORIGIN")
    assert_equal "secret-token", factory.options.fetch(:environment).fetch("HQBASE_ACCESS_TOKEN")
    assert_equal "mailbox-1", factory.options.fetch(:environment).fetch("PRISM_MAIL_MAILBOX_ID")
    refute_includes factory.options.fetch(:command).join(" "), "secret-token"
  end

  def test_rejects_an_artifact_for_another_mailbox
    artifact = valid_artifact.merge("mailbox_id" => "mailbox-2")
    gateway = gateway_for(result: success_result(artifact))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.execute(**request, access_token: "secret-token")
    end

    assert_equal "hub.mail.response.invalid_artifact", error.code
  end

  def test_rejects_inconsistent_artifact_counts
    artifact = valid_artifact.merge("omitted_count" => 3)
    gateway = gateway_for(result: success_result(artifact))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.execute(**request, access_token: "secret-token")
    end

    assert_equal "hub.mail.response.invalid_artifact", error.code
  end

  def test_maps_worker_timeout_without_logging_secrets
    log = StringIO.new
    gateway = gateway_for(
      result: result(stdout: "", exit_status: nil, timed_out: true),
      logger: Logger.new(log)
    )

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.execute(**request, access_token: "secret-token")
    end

    assert_equal "hub.mail.process.timeout", error.code
    refute_includes log.string, "secret-token"
  end

  def test_maps_process_start_failure_to_mail_namespace
    start_error = PrismHub::Adapters::ProcessRunner::StartError.new("Errno::ENOENT")
    runner = FakeRunner.new(error: start_error)
    gateway = gateway_for(runner_factory: CapturingFactory.new(runner))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.execute(**request, access_token: "secret-token")
    end

    assert_equal "hub.mail.process.unavailable", error.code
    assert_equal({"system_error" => "Errno::ENOENT"}, error.details)
  end

  private

  def request
    {
      mailbox_id: "mailbox-1",
      since: "2026-09-10T00:00:00Z",
      before: "2026-09-11T00:00:00Z"
    }
  end

  def valid_artifact
    {
      "schema_version" => "prism-mail.digest.v1",
      "mode" => "extractive",
      "mailbox_id" => "mailbox-1",
      "window" => {
        "since" => "2026-09-10T00:00:00Z",
        "before" => "2026-09-11T00:00:00Z"
      },
      "matched_count" => 1,
      "selected_count" => 1,
      "omitted_count" => 0,
      "entries" => [
        {
          "kind" => "source_excerpt",
          "evidence" => {"message_id" => "message-1"}
        }
      ]
    }
  end

  def gateway_for(result: nil, runner_factory: nil, logger: Logger.new(StringIO.new))
    runner_factory ||= CapturingFactory.new(FakeRunner.new(result: result))
    PrismHub::Adapters::SubprocessMailExecutionGateway.new(
      command: ["prism-mail"],
      origin: "https://mail.example.test",
      logger: logger,
      runner_factory: runner_factory
    )
  end

  def success_result(artifact)
    result(stdout: JSON.generate(artifact), exit_status: 0)
  end

  def result(stdout:, exit_status:, timed_out: false)
    Result.new(
      stdout: stdout,
      stderr: "",
      exit_status: exit_status,
      timed_out: timed_out,
      stdout_too_large: false,
      stderr_too_large: false
    )
  end
end
