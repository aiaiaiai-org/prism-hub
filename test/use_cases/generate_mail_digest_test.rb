# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class GenerateMailDigestTest < Minitest::Test
  Credential = Data.define(
    :provider,
    :origin,
    :resource,
    :oauth_client_id,
    :access_token,
    :refresh_token,
    :scope,
    :token_type,
    :expires_at
  )

  class Repository
    attr_reader :fetches, :stores

    def initialize(credential)
      @credential = credential
      @fetches = []
      @stores = []
    end

    def fetch(**identity)
      @fetches << identity
      @credential
    end

    def store(**attributes)
      @stores << attributes
      @credential = Credential.new(**attributes)
    end
  end

  class ExecutionGateway
    attr_reader :calls

    def initialize
      @calls = []
    end

    def execute(**attributes)
      @calls << attributes
      {
        "schema_version" => "prism-mail.digest.v1",
        "mode" => "extractive",
        "mailbox_id" => attributes.fetch(:mailbox_id),
        "window" => {"since" => attributes.fetch(:since), "before" => attributes.fetch(:before)},
        "matched_count" => 0,
        "selected_count" => 0,
        "omitted_count" => 0,
        "entries" => []
      }
    end
  end

  class OauthGateway
    attr_reader :calls

    def initialize(results = [])
      @results = results.dup
      @calls = []
    end

    def refresh(**attributes)
      @calls << attributes
      @results.shift or raise "unexpected refresh"
    end
  end

  def test_resolves_server_side_credential_and_canonicalizes_window
    repository = Repository.new(valid_credential)
    execution_gateway = ExecutionGateway.new
    oauth_gateway = OauthGateway.new
    use_case = build_use_case(
      repository: repository,
      execution_gateway: execution_gateway,
      oauth_gateway: oauth_gateway
    )

    artifact = use_case.call(
      mailbox_id: "mailbox-1",
      since: "2026-09-11T20:00:00+03:00",
      before: "2026-09-11T21:00:00+03:00"
    )

    assert_equal "secret-access-token", execution_gateway.calls.fetch(0).fetch(:access_token)
    assert_equal "2026-09-11T17:00:00Z", execution_gateway.calls.fetch(0).fetch(:since)
    assert_equal "2026-09-11T18:00:00Z", execution_gateway.calls.fetch(0).fetch(:before)
    assert_equal "prism-mail.digest.v1", artifact.fetch("schema_version")
    assert_empty oauth_gateway.calls
  end

  def test_rotates_expiring_credential_before_worker_execution
    repository = Repository.new(valid_credential(expires_at: Time.utc(2026, 9, 11, 18, 0, 30)))
    execution_gateway = ExecutionGateway.new
    oauth_gateway = OauthGateway.new([refreshed_result])

    build_use_case(
      repository: repository,
      execution_gateway: execution_gateway,
      oauth_gateway: oauth_gateway
    ).call(**request)

    assert_equal [
      {client_id: "client-prism", refresh_token: "secret-refresh-token"}
    ], oauth_gateway.calls
    stored = repository.stores.fetch(0)
    assert_equal "rotated-access-token", stored.fetch(:access_token)
    assert_equal "rotated-refresh-token", stored.fetch(:refresh_token)
    assert_equal Time.utc(2026, 9, 11, 19, 0, 0), stored.fetch(:expires_at)
    assert_equal "rotated-access-token", execution_gateway.calls.fetch(0).fetch(:access_token)
  end

  def test_requires_reconnect_for_legacy_credential_without_client_identity
    repository = Repository.new(
      valid_credential(oauth_client_id: nil, expires_at: Time.utc(2026, 9, 11, 17, 59, 59))
    )
    execution_gateway = ExecutionGateway.new
    oauth_gateway = OauthGateway.new

    error = assert_raises(PrismHub::AuthorisationError) do
      build_use_case(
        repository: repository,
        execution_gateway: execution_gateway,
        oauth_gateway: oauth_gateway
      ).call(**request)
    end

    assert_equal "hub.mail.credential.reconnect_required", error.code
    assert_empty oauth_gateway.calls
    assert_empty execution_gateway.calls
  end

  def test_requires_reconnect_when_refresh_grant_is_invalid
    repository = Repository.new(valid_credential(expires_at: Time.utc(2026, 9, 11, 17, 59, 59)))
    execution_gateway = ExecutionGateway.new
    oauth_gateway = OauthGateway.new([invalid_grant_result])

    error = assert_raises(PrismHub::AuthorisationError) do
      build_use_case(
        repository: repository,
        execution_gateway: execution_gateway,
        oauth_gateway: oauth_gateway
      ).call(**request)
    end

    assert_equal "hub.mail.credential.reconnect_required", error.code
    assert_empty repository.stores
    assert_empty execution_gateway.calls
  end

  def test_rejects_missing_credential_before_worker_execution
    repository = Repository.new(nil)
    execution_gateway = ExecutionGateway.new
    error = assert_raises(PrismHub::CredentialNotFoundError) do
      build_use_case(
        repository: repository,
        execution_gateway: execution_gateway,
        oauth_gateway: OauthGateway.new
      ).call(**request)
    end

    assert_equal "hub.mail.credential.not_found", error.code
    assert_empty execution_gateway.calls
  end

  def test_rejects_credential_without_mail_read_scope
    repository = Repository.new(valid_credential(scope: ["offline_access"]))
    execution_gateway = ExecutionGateway.new
    error = assert_raises(PrismHub::AuthorisationError) do
      build_use_case(
        repository: repository,
        execution_gateway: execution_gateway,
        oauth_gateway: OauthGateway.new
      ).call(**request)
    end

    assert_equal "hub.mail.credential.scope_missing", error.code
    assert_empty execution_gateway.calls
  end

  def test_rejects_invalid_window_before_credential_resolution
    repository = Repository.new(valid_credential)
    execution_gateway = ExecutionGateway.new
    error = assert_raises(PrismHub::InputError) do
      build_use_case(
        repository: repository,
        execution_gateway: execution_gateway,
        oauth_gateway: OauthGateway.new
      ).call(
        mailbox_id: "mailbox-1",
        since: "2026-09-11T18:00:00Z",
        before: "2026-09-11T18:00:00Z"
      )
    end

    assert_equal "hub.mail.window.invalid", error.code
    assert_empty repository.fetches
    assert_empty execution_gateway.calls
  end

  private

  def build_use_case(repository:, execution_gateway:, oauth_gateway:)
    PrismHub::UseCases::GenerateMailDigest.new(
      credential_repository: repository,
      execution_gateway: execution_gateway,
      oauth_gateway: oauth_gateway,
      provider: "hqbase",
      origin: "https://mail.aiaiaiai.org",
      resource: "https://mail.aiaiaiai.org/api/v1",
      clock: -> { Time.utc(2026, 9, 11, 18, 0, 0) }
    )
  end

  def valid_credential(**overrides)
    defaults = {
      provider: "hqbase",
      origin: "https://mail.aiaiaiai.org",
      resource: "https://mail.aiaiaiai.org/api/v1",
      oauth_client_id: "client-prism",
      access_token: "secret-access-token",
      refresh_token: "secret-refresh-token",
      scope: %w[mail:read offline_access],
      token_type: "Bearer",
      expires_at: Time.utc(2026, 9, 11, 19, 0, 0)
    }
    Credential.new(**defaults.merge(overrides))
  end

  def refreshed_result
    PrismHub::Adapters::HqbaseDeviceOauthGateway::Refresh.new(
      status: :refreshed,
      access_token: "rotated-access-token",
      refresh_token: "rotated-refresh-token",
      scope: %w[mail:read offline_access],
      token_type: "Bearer",
      expires_in: 3600,
      error: nil
    )
  end

  def invalid_grant_result
    PrismHub::Adapters::HqbaseDeviceOauthGateway::Refresh.new(
      status: :invalid_grant,
      access_token: nil,
      refresh_token: nil,
      scope: [],
      token_type: nil,
      expires_in: nil,
      error: "invalid_grant"
    )
  end

  def request
    {
      mailbox_id: "mailbox-1",
      since: "2026-09-11T17:00:00Z",
      before: "2026-09-11T18:00:00Z"
    }
  end
end
