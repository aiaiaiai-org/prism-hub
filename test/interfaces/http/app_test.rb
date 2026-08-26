# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class HttpAppTest < Minitest::Test
  TOKEN = "test-hub-token-that-is-longer-than-32-characters"

  def test_health_is_public
    response = request.get("/healthz")

    assert_equal 200, response.status
    assert_equal "request-test-1", response["x-request-id"]
  end

  def test_api_requires_bearer_authentication
    response = request.get("/api/v1/channels")

    assert_equal 401, response.status
    assert_equal "request-test-1", response["x-request-id"]
    assert_equal "request-test-1", JSON.parse(response.body).fetch("request_id")
  end

  def test_channels_expose_capabilities_and_page_metadata
    response = request.get(
      "/api/v1/channels?limit=1",
      "HTTP_AUTHORIZATION" => "Bearer #{TOKEN}"
    )

    payload = JSON.parse(response.body)
    assert_equal 200, response.status
    assert_equal ["post"], payload.dig("channels", 0, "capabilities", "formats")
    assert_equal 1, payload.dig("page", "limit")
    assert_nil payload.dig("page", "next_cursor")
  end

  def test_publish_accepts_only_public_channel_ids
    response = request.post(
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

  def request
    @request ||= Rack::MockRequest.new(build_app)
  end

  def build_app
    channels = PrismHubTestSupport.channels
    gateway = PrismHubTestSupport::FakeExecutionGateway.new
    request_ids = PrismHubTestSupport::FixedRequestIdFactory.new
    use_case = PrismHub::UseCases::ExecutePublication.new(
      operation: "publish",
      channel_repository: channels,
      execution_gateway: gateway
    )

    PrismHub::Interfaces::Http::App.new(
      authenticator: PrismHub::Interfaces::Http::Authenticator.new(token: TOKEN),
      health_endpoint: PrismHub::Interfaces::Http::HealthEndpoint.new,
      routes: {
        ["GET", "/api/v1/channels"] => PrismHub::Interfaces::Http::ChannelsEndpoint.new(
          list_channels: PrismHub::UseCases::ListChannels.new(channel_repository: channels)
        ),
        ["POST", "/api/v1/publications"] => PrismHub::Interfaces::Http::PublicationEndpoint.new(
          execute_publication: use_case,
          request_body: PrismHub::Interfaces::Http::RequestBody.new
        )
      },
      logger: Logger.new(StringIO.new),
      request_id_factory: request_ids
    )
  end
end
