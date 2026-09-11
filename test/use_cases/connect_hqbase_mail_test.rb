# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class ConnectHqbaseMailTest < Minitest::Test
  Gateway = Struct.new(:starts, :polls, :origin, :resource) do
    def start
      starts.shift
    end

    def poll(client_id:, device_code:)
      raise "wrong client" unless client_id == "client-prism"
      raise "wrong device code" unless device_code == "device-secret"

      polls.shift
    end
  end

  class Repository
    attr_reader :stored

    def store(**attributes)
      @stored = attributes
    end
  end

  def test_waits_for_approval_and_stores_tokens_server_side
    gateway = Gateway.new(
      [start_authorization],
      [pending_result, connected_result],
      "https://mail.aiaiaiai.org",
      "https://mail.aiaiaiai.org/api/v1"
    )
    repository = Repository.new
    sleeps = []
    now = Time.utc(2026, 9, 11, 18, 0, 0)
    use_case = PrismHub::UseCases::ConnectHqbaseMail.new(
      gateway: gateway,
      credential_repository: repository,
      clock: -> { now },
      sleeper: ->(seconds) { sleeps << seconds }
    )

    authorization = use_case.start
    result = use_case.complete(authorization: authorization)

    assert_equal [5], sleeps
    assert_equal "connected", result.fetch("status")
    assert_equal "hqb_access_secret", repository.stored.fetch(:access_token)
    assert_equal "hqb_refresh_secret", repository.stored.fetch(:refresh_token)
    assert_equal "https://mail.aiaiaiai.org/api/v1", repository.stored.fetch(:resource)
  end

  def test_slow_down_increases_poll_interval
    gateway = Gateway.new(
      [start_authorization],
      [pending_result(error: "slow_down"), connected_result],
      "https://mail.aiaiaiai.org",
      "https://mail.aiaiaiai.org/api/v1"
    )
    sleeps = []
    now = Time.utc(2026, 9, 11, 18, 0, 0)
    use_case = PrismHub::UseCases::ConnectHqbaseMail.new(
      gateway: gateway,
      credential_repository: Repository.new,
      clock: -> { now },
      sleeper: ->(seconds) { sleeps << seconds }
    )

    use_case.complete(authorization: use_case.start)

    assert_equal [10], sleeps
  end

  private

  def start_authorization
    PrismHub::Adapters::HqbaseDeviceOauthGateway::Start.new(
      client_id: "client-prism",
      device_code: "device-secret",
      user_code: "ABCD-EFGH",
      verification_uri: "https://mail.aiaiaiai.org/device",
      verification_uri_complete: "https://mail.aiaiaiai.org/device?user_code=ABCD-EFGH",
      expires_in: 900,
      interval: 5
    )
  end

  def pending_result(error: "authorization_pending")
    PrismHub::Adapters::HqbaseDeviceOauthGateway::Poll.new(
      status: :pending,
      access_token: nil,
      refresh_token: nil,
      scope: [],
      token_type: nil,
      expires_in: nil,
      error: error
    )
  end

  def connected_result
    PrismHub::Adapters::HqbaseDeviceOauthGateway::Poll.new(
      status: :connected,
      access_token: "hqb_access_secret",
      refresh_token: "hqb_refresh_secret",
      scope: %w[mail:read offline_access],
      token_type: "Bearer",
      expires_in: 3600,
      error: nil
    )
  end
end
