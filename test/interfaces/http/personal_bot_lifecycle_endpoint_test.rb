# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class PersonalBotLifecycleEndpointTest < Minitest::Test
  class Lifecycle
    attr_reader :calls

    def initialize
      @calls = []
    end

    def status(**arguments)
      @calls << arguments
      PrismHub::Domain::BotInstance.new(
        id: "private-instance-id",
        principal_id: "private-principal",
        workspace_id: "private-workspace",
        status: "paused",
        paused_at: Time.utc(2026, 8, 28, 4, 30)
      )
    end
  end

  def setup
    @lifecycle = Lifecycle.new
    @endpoint = PrismHub::Interfaces::Http::PersonalBotLifecycleEndpoint.new(
      lifecycle: @lifecycle,
      operation: :status,
      request_body: PrismHub::Interfaces::Http::RequestBody.new
    )
  end

  def test_returns_only_public_lifecycle_status
    status, _headers, body = @endpoint.call(
      request(
        "provider" => "telegram",
        "provider_scope" => "global",
        "subject_id" => "123456789"
      ),
      authorisation_context: authorisation_context
    )

    assert_equal 200, status
    assert_equal({"bot_instance" => {"status" => "paused"}}, JSON.parse(body.join))
    refute_includes body.join, "private-instance-id"
    refute_includes body.join, "private-workspace"
    refute_includes body.join, "123456789"
  end

  def test_rejects_internal_ids_and_non_string_provider_evidence
    invalid_payloads = [
      {"provider" => "telegram", "provider_scope" => "global"},
      {"provider" => "telegram", "provider_scope" => "global", "subject_id" => 123},
      {
        "provider" => "telegram",
        "provider_scope" => "global",
        "subject_id" => "123456789",
        "workspace_id" => "caller-controlled"
      }
    ]

    invalid_payloads.each do |payload|
      error = assert_raises(PrismHub::InputError) do
        @endpoint.call(request(payload), authorisation_context: authorisation_context)
      end
      assert_equal "hub.bot_instance.request.invalid", error.code
    end
    assert_empty @lifecycle.calls
  end

  private

  def request(payload)
    Rack::Request.new(
      Rack::MockRequest.env_for(
        "/api/v1/bot-instances/personal/status",
        method: "POST",
        "CONTENT_TYPE" => "application/json",
        input: JSON.generate(payload)
      )
    )
  end

  def authorisation_context
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-client",
      capabilities: [PrismHub::Domain::Capabilities::BOT_INSTANCES_READ],
      allowed_channel_ids: []
    )
  end
end
