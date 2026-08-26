# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class SubprocessExecutionGatewayTest < Minitest::Test
  Result = PrismHub::Adapters::ProcessRunner::Result

  class FakeRunner
    def initialize(result)
      @result = result
    end

    def call(_input)
      @result
    end
  end

  def test_rejects_a_mismatched_request_id
    response = {
      "protocol_version" => "prism-execution.v1",
      "request_id" => "wrong",
      "status" => "ok",
      "result" => {}
    }
    gateway = gateway_for(stdout: JSON.generate(response))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.execute(envelope)
    end

    assert_equal "hub.prism.response.invalid_envelope", error.code
  end

  def test_maps_a_timeout_without_retrying
    gateway = gateway_for(stdout: "", timed_out: true, exit_status: nil)

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.execute(envelope)
    end

    assert_equal "hub.prism.process.timeout", error.code
  end

  private

  def envelope
    {
      "protocol_version" => "prism-execution.v1",
      "request_id" => "request-1",
      "operation" => "validate",
      "payload" => {}
    }
  end

  def gateway_for(stdout:, timed_out: false, exit_status: 0)
    result = Result.new(
      stdout: stdout,
      stderr: "",
      exit_status: exit_status,
      timed_out: timed_out,
      stdout_too_large: false,
      stderr_too_large: false
    )
    PrismHub::Adapters::SubprocessExecutionGateway.new(
      runner: FakeRunner.new(result),
      logger: Logger.new(StringIO.new)
    )
  end
end
