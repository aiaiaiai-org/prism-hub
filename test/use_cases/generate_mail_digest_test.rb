# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class GenerateMailDigestTest < Minitest::Test
  Credential = Data.define(:access_token, :refresh_token, :scope, :token_type, :expires_at)

  class Repository
    attr_reader :fetches

    def initialize(credential)
      @credential = credential
      @fetches = []
    end

    def fetch(**identity)
      @fetches << identity
      @credential
    end
  end

  class Gateway
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

  def test_resolves_server_side_credential_and_canonicalizes_window
    repository = Repository.new(valid_credential)
    gateway = Gateway.new
    use_case = build_use_case(repository: repository, gateway: gateway)

    artifact = use_case.call(
      mailbox_id: "mailbox-1",
      since: "2026-09-11T20:00:00+03:00",
      before: "2026-09-11T21:00:00+03:00"
    )

    assert_equal [
      {provider: "hqbase", origin: "https://mail.aiaiaiai.org", resource: "https://mail.aiaiaiai.org/api/v1"}
    ], repository.fetches
    assert_equal "secret-access-token", gateway.calls.fetch(0).fetch(:access_token)
    assert_equal "2026-09-11T17:00:00Z", gateway.calls.fetch(0).fetch(:since)
    assert_equal "2026-09-11T18:00:00Z", gateway.calls.fetch(0).fetch(:before)
    assert_equal "prism-mail.digest.v1", artifact.fetch("schema_version")
  end

  def test_rejects_missing_credential_before_worker_execution
    repository = Repository.new(nil)
    gateway = Gateway.new
    error = assert_raises(PrismHub::CredentialNotFoundError) do
      build_use_case(repository: repository, gateway: gateway).call(**request)
    end

    assert_equal "hub.mail.credential.not_found", error.code
    assert_empty gateway.calls
  end

  def test_rejects_expired_access_token_before_worker_execution
    repository = Repository.new(valid_credential(expires_at: Time.utc(2026, 9, 11, 17, 59, 59)))
    gateway = Gateway.new
    error = assert_raises(PrismHub::AuthorisationError) do
      build_use_case(repository: repository, gateway: gateway).call(**request)
    end

    assert_equal "hub.mail.credential.expired", error.code
    assert_empty gateway.calls
  end

  def test_rejects_credential_without_mail_read_scope
    repository = Repository.new(valid_credential(scope: ["offline_access"]))
    gateway = Gateway.new
    error = assert_raises(PrismHub::AuthorisationError) do
      build_use_case(repository: repository, gateway: gateway).call(**request)
    end

    assert_equal "hub.mail.credential.scope_missing", error.code
    assert_empty gateway.calls
  end

  def test_rejects_invalid_window_before_credential_resolution
    repository = Repository.new(valid_credential)
    gateway = Gateway.new
    error = assert_raises(PrismHub::InputError) do
      build_use_case(repository: repository, gateway: gateway).call(
        mailbox_id: "mailbox-1",
        since: "2026-09-11T18:00:00Z",
        before: "2026-09-11T18:00:00Z"
      )
    end

    assert_equal "hub.mail.window.invalid", error.code
    assert_empty repository.fetches
    assert_empty gateway.calls
  end

  private

  def build_use_case(repository:, gateway:)
    PrismHub::UseCases::GenerateMailDigest.new(
      credential_repository: repository,
      execution_gateway: gateway,
      provider: "hqbase",
      origin: "https://mail.aiaiaiai.org",
      resource: "https://mail.aiaiaiai.org/api/v1",
      clock: -> { Time.utc(2026, 9, 11, 18, 0, 0) }
    )
  end

  def valid_credential(**overrides)
    defaults = {
      access_token: "secret-access-token",
      refresh_token: "secret-refresh-token",
      scope: %w[mail:read offline_access],
      token_type: "Bearer",
      expires_at: Time.utc(2026, 9, 11, 19, 0, 0)
    }
    Credential.new(**defaults.merge(overrides))
  end

  def request
    {
      mailbox_id: "mailbox-1",
      since: "2026-09-11T17:00:00Z",
      before: "2026-09-11T18:00:00Z"
    }
  end
end
