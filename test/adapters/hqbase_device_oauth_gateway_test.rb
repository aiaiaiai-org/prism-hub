# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class HqbaseDeviceOauthGatewayTest < Minitest::Test
  class Transport
    attr_reader :requests

    def initialize(responses)
      @responses = responses.dup
      @requests = []
    end

    def call(uri:, headers:, body:)
      @requests << {uri: uri, headers: headers, body: body}
      @responses.shift or raise "unexpected request"
    end
  end

  def test_starts_v1_device_authorization_with_minimal_read_scope
    transport = Transport.new(
      [
        {status: 201, body: JSON.generate("client_id" => "client-prism")},
        {
          status: 200,
          body: JSON.generate(
            "device_code" => "device-secret",
            "user_code" => "ABCD-EFGH",
            "verification_uri" => "https://mail.aiaiaiai.org/device",
            "verification_uri_complete" => "https://mail.aiaiaiai.org/device?user_code=ABCD-EFGH",
            "expires_in" => 900,
            "interval" => 5
          )
        }
      ]
    )
    gateway = PrismHub::Adapters::HqbaseDeviceOauthGateway.new(
      origin: "https://mail.aiaiaiai.org",
      transport: transport
    )

    authorization = gateway.start

    assert_equal "client-prism", authorization.client_id
    assert_equal "device-secret", authorization.device_code
    assert_equal "ABCD-EFGH", authorization.user_code
    assert_equal "https://mail.aiaiaiai.org/api/v1", gateway.resource

    registration = transport.requests.fetch(0)
    assert_equal "/api/auth/oauth2/register", registration.fetch(:uri).path
    registration_body = JSON.parse(registration.fetch(:body))
    assert_equal ["https://mail.aiaiaiai.org/api/v1"], registration_body.fetch("resources")
    assert_equal "mail:read offline_access", registration_body.fetch("scope")
    assert_equal "none", registration_body.fetch("token_endpoint_auth_method")

    authorization_request = transport.requests.fetch(1)
    assert_equal "/api/auth/device/code", authorization_request.fetch(:uri).path
    form = URI.decode_www_form(authorization_request.fetch(:body)).to_h
    assert_equal "https://mail.aiaiaiai.org/api/v1", form.fetch("resource")
    assert_equal "mail:read offline_access", form.fetch("scope")
  end

  def test_maps_pending_and_connected_token_responses
    transport = Transport.new(
      [
        {status: 400, body: JSON.generate("error" => "authorization_pending")},
        {
          status: 200,
          body: JSON.generate(
            "access_token" => "hqb_access_secret",
            "refresh_token" => "hqb_refresh_secret",
            "scope" => "mail:read offline_access",
            "token_type" => "Bearer",
            "expires_in" => 3600
          )
        }
      ]
    )
    gateway = PrismHub::Adapters::HqbaseDeviceOauthGateway.new(
      origin: "https://mail.aiaiaiai.org",
      transport: transport
    )

    pending = gateway.poll(client_id: "client-prism", device_code: "device-secret")
    connected = gateway.poll(client_id: "client-prism", device_code: "device-secret")

    assert_equal :pending, pending.status
    assert_equal "authorization_pending", pending.error
    assert_equal :connected, connected.status
    assert_equal "hqb_access_secret", connected.access_token
    assert_equal "hqb_refresh_secret", connected.refresh_token
    assert_equal %w[mail:read offline_access], connected.scope
  end

  def test_rejects_non_origin_configuration
    error = assert_raises(PrismHub::ConfigurationError) do
      PrismHub::Adapters::HqbaseDeviceOauthGateway.new(origin: "https://mail.aiaiaiai.org/path")
    end

    assert_equal "hub.mail.hqbase_origin.invalid", error.code
  end
end
