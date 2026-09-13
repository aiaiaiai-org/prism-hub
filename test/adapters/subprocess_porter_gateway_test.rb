# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class SubprocessPorterGatewayTest < Minitest::Test
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

  def test_sends_only_the_provider_neutral_worker_contract
    runner = FakeRunner.new(result: success_result(valid_intent))
    factory = CapturingFactory.new(runner)
    gateway = gateway_for(runner_factory: factory)

    intent = gateway.build_delivery_intent(
      artifact: artifact,
      routes: routes,
      chunk_max_chars: 3500
    )
    request = JSON.parse(runner.input)

    assert_instance_of PrismHub::Domain::DeliveryIntent, intent
    assert_equal ["prism-porter"], factory.options.fetch(:command)
    assert_equal({}, factory.options.fetch(:environment))
    assert_equal "prism-porter.request.v1", request.fetch("schema_version")
    assert_equal artifact, request.fetch("artifact")
    assert_equal routes, request.fetch("routes")
    assert_equal 3500, request.fetch("chunk_max_chars")
    refute request.key?("telegram")
    refute request.key?("provider_credentials")
  end

  def test_rejects_a_response_for_another_logical_context
    response = valid_intent.merge(
      "logical_context" => {"workspace" => "personal", "channel" => "other"}
    )
    response["idempotency_key"] = fingerprint(response)
    gateway = gateway_for(result: success_result(response))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.build_delivery_intent(artifact: artifact, routes: routes)
    end

    assert_equal "hub.porter.response.mismatch", error.code
  end

  def test_rejects_a_forged_worker_idempotency_key
    response = valid_intent.merge("idempotency_key" => "0" * 64)
    gateway = gateway_for(result: success_result(response))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.build_delivery_intent(artifact: artifact, routes: routes)
    end

    assert_equal "hub.porter.response.invalid_intent", error.code
  end

  def test_rejects_a_route_policy_without_the_artifact_kind
    gateway = gateway_for(result: success_result(valid_intent))

    error = assert_raises(PrismHub::InputError) do
      gateway.build_delivery_intent(
        artifact: artifact,
        routes: [
          {
            "artifact_kind" => "mail.invitation",
            "logical_context" => {"workspace" => "personal", "channel" => "digest"}
          }
        ]
      )
    end

    assert_equal "hub.porter.request.invalid", error.code
  end

  def test_maps_worker_timeout_without_reflecting_payload
    log = StringIO.new
    gateway = gateway_for(
      result: result(stdout: "", exit_status: nil, timed_out: true),
      logger: Logger.new(log)
    )

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.build_delivery_intent(artifact: artifact, routes: routes)
    end

    assert_equal "hub.porter.process.timeout", error.code
    refute_includes log.string, "Digest body"
  end

  def test_maps_process_start_failure_to_porter_namespace
    start_error = PrismHub::Adapters::ProcessRunner::StartError.new("Errno::ENOENT")
    runner = FakeRunner.new(error: start_error)
    gateway = gateway_for(runner_factory: CapturingFactory.new(runner))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.build_delivery_intent(artifact: artifact, routes: routes)
    end

    assert_equal "hub.porter.process.unavailable", error.code
    assert_equal({"system_error" => "Errno::ENOENT"}, error.details)
  end

  private

  def artifact
    {
      "artifact_kind" => "mail.digest",
      "artifact_id" => "artifact-1",
      "payload" => {"text" => "Digest body"}
    }
  end

  def routes
    [
      {
        "artifact_kind" => "mail.digest",
        "logical_context" => {"workspace" => "personal", "channel" => "digest"}
      }
    ]
  end

  def valid_intent
    value = {
      "schema_version" => "prism-porter.delivery-intent.v1",
      "artifact_id" => "artifact-1",
      "artifact_kind" => "mail.digest",
      "logical_context" => {"workspace" => "personal", "channel" => "digest"},
      "presentation" => {"format" => "plain_text"},
      "chunks" => [{"text" => "Digest body", "position" => 1, "total" => 1}]
    }
    value.merge("idempotency_key" => fingerprint(value))
  end

  def fingerprint(value)
    Digest::SHA256.hexdigest([
      value.fetch("artifact_kind"),
      value.fetch("artifact_id"),
      value.fetch("logical_context").fetch("workspace"),
      value.fetch("logical_context").fetch("channel"),
      value.fetch("presentation").fetch("format"),
      value.fetch("chunks").map { |chunk| chunk.fetch("text") }.join
    ].join("\0"))
  end

  def gateway_for(result: nil, runner_factory: nil, logger: Logger.new(StringIO.new))
    runner_factory ||= CapturingFactory.new(FakeRunner.new(result: result))
    PrismHub::Adapters::SubprocessPorterGateway.new(
      command: ["prism-porter"],
      logger: logger,
      runner_factory: runner_factory
    )
  end

  def success_result(intent)
    result(stdout: JSON.generate(intent), exit_status: 0)
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
