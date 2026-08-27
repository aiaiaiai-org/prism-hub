# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class HttpAppTest < Minitest::Test
  TOKEN = "prism_client_v1_#{'a' * 43}".freeze
  NOW = Time.utc(2026, 8, 27, 10, 53, 0)

  class FakeCredentialRepository < PrismHub::Ports::ClientCredentialRepository
    def initialize(token:, context:)
      @token = token
      @context = context
    end

    def authenticate(token:, now:)
      token == @token && now == NOW ? @context : nil
    end
  end

  def test_health_is_public
    response = request_for(full_context).get("/healthz")

    assert_equal 200, response.status
    assert_equal "request-test-1", response["x-request-id"]
  end

  def test_api_returns_401_without_a_valid_bearer_credential
    response = request_for(full_context).get("/api/v1/channels")

    assert_equal 401, response.status
    assert_equal "request-test-1", response["x-request-id"]
    assert_equal "hub.authorization.required", JSON.parse(response.body).dig("error", "code")
  end

  def test_channels_return_only_resources_granted_to_the_principal
    response = request_for(
      context(
        capabilities: [PrismHub::Domain::Capabilities::CHANNELS_READ],
        channels: ["personal-threads"]
      )
    ).get(
      "/api/v1/channels?limit=10",
      "HTTP_AUTHORIZATION" => "Bearer #{TOKEN}"
    )

    payload = JSON.parse(response.body)
    assert_equal 200, response.status
    assert_equal ["personal-threads"], payload.fetch("channels").map { |channel| channel.fetch("id") }
  end

  def test_valid_principal_without_required_capability_gets_403
    response = request_for(
      context(capabilities: [], channels: ["personal-threads"])
    ).get(
      "/api/v1/channels",
      "HTTP_AUTHORIZATION" => "Bearer #{TOKEN}"
    )

    assert_equal 403, response.status
    assert_equal "hub.authorization.capability_denied", JSON.parse(response.body).dig("error", "code")
  end

  def test_publication_with_any_ungranted_target_is_rejected_as_a_whole
    gateway = PrismHubTestSupport::FakeExecutionGateway.new
    value = PrismHubTestSupport.publication_hash
    value.fetch("targets") << {
      "id" => "instagram-post",
      "channel_id" => "personal-instagram",
      "selection" => {"mode" => "exact", "variant_id" => "personal-post"}
    }

    response = request_for(
      context(
        capabilities: [PrismHub::Domain::Capabilities::PUBLICATIONS_PUBLISH],
        channels: ["personal-threads"]
      ),
      gateway: gateway
    ).post(
      "/api/v1/publications",
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{TOKEN}",
      "HTTP_IDEMPOTENCY_KEY" => "telegram:42:100",
      input: JSON.generate(value)
    )

    assert_equal 403, response.status
    assert_equal "hub.authorization.channel_denied", JSON.parse(response.body).dig("error", "code")
    assert_empty gateway.envelopes
  end

  def test_authorised_publication_reaches_prism_execution
    response = request_for(full_context).post(
      "/api/v1/publications",
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{TOKEN}",
      "HTTP_IDEMPOTENCY_KEY" => "telegram:42:100",
      input: JSON.generate(PrismHubTestSupport.publication_hash)
    )

    assert_equal 200, response.status
    assert_equal "ok", JSON.parse(response.body).fetch("status")
  end

  private

  def request_for(authorisation_context, gateway: PrismHubTestSupport::FakeExecutionGateway.new)
    Rack::MockRequest.new(build_app(authorisation_context, gateway))
  end

  def build_app(authorisation_context, gateway)
    channels = configured_channels
    request_ids = PrismHubTestSupport::FixedRequestIdFactory.new
    publish = PrismHub::UseCases::ExecutePublication.new(
      operation: "publish",
      channel_repository: channels,
      execution_gateway: gateway
    )

    repository = FakeCredentialRepository.new(token: TOKEN, context: authorisation_context)
    PrismHub::Interfaces::Http::App.new(
      authenticator: PrismHub::Interfaces::Http::Authenticator.new(
        credential_repository: repository,
        clock: -> { NOW }
      ),
      health_endpoint: PrismHub::Interfaces::Http::HealthEndpoint.new,
      routes: {
        ["GET", "/api/v1/channels"] => PrismHub::Interfaces::Http::ChannelsEndpoint.new(
          list_channels: PrismHub::UseCases::ListChannels.new(channel_repository: channels)
        ),
        ["POST", "/api/v1/publications"] => PrismHub::Interfaces::Http::PublicationEndpoint.new(
          execute_publication: publish,
          request_body: PrismHub::Interfaces::Http::RequestBody.new
        )
      },
      logger: Logger.new(StringIO.new),
      request_id_factory: request_ids
    )
  end

  def configured_channels
    values = [
      channel("personal-threads", "meta.threads", "0x0sky", "threads.personal"),
      channel("personal-instagram", "meta.instagram", "0x0sky", "instagram.personal")
    ]
    PrismHub::Adapters::EnvironmentChannelRepository.new(JSON.generate(values))
  end

  def channel(id, provider_id, channel_ref, credential_ref)
    {
      "id" => id,
      "label" => id,
      "provider_id" => provider_id,
      "channel_ref" => channel_ref,
      "credential_ref" => credential_ref,
      "capabilities" => {
        "formats" => ["post"],
        "text" => true,
        "media_kinds" => []
      }
    }
  end

  def full_context
    context(
      capabilities: PrismHub::Domain::Capabilities::ALL,
      channels: %w[personal-instagram personal-threads]
    )
  end

  def context(capabilities:, channels:)
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-personal",
      workspace_id: "personal",
      capabilities: capabilities,
      allowed_channel_ids: channels
    )
  end
end
