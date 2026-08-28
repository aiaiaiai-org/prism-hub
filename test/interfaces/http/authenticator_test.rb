# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class HttpAuthenticatorTest < Minitest::Test
  TOKEN = "prism_client_v1_#{'a' * 43}".freeze
  LEGACY_TOKEN = "legacy-token-that-is-longer-than-thirty-two-characters".freeze
  NOW = Time.utc(2026, 8, 27, 10, 53, 0)

  class FakeCredentialRepository < PrismHub::Ports::ClientCredentialRepository
    attr_reader :last_authentication

    def initialize(token:, context:)
      @token = token
      @context = context
    end

    def authenticate(token:, now:)
      @last_authentication = {token: token, now: now}
      token == @token ? @context : nil
    end
  end

  def test_resolves_scoped_bearer_credential_to_authorisation_context
    context = context_for(["personal-threads"])
    repository = FakeCredentialRepository.new(token: TOKEN, context: context)
    authenticator = build_authenticator(repository)

    resolved = authenticator.authenticate(request_with(TOKEN))

    assert_same context, resolved
    assert_equal({token: TOKEN, now: NOW}, repository.last_authentication)
  end

  def test_missing_or_malformed_bearer_credentials_do_not_authenticate
    repository = FakeCredentialRepository.new(token: TOKEN, context: context_for([]))
    authenticator = build_authenticator(repository)

    assert_nil authenticator.authenticate(Rack::Request.new({}))
    assert_nil authenticator.authenticate(request_with("bad token"))
  end

  def test_legacy_token_is_disabled_unless_explicitly_configured
    repository = FakeCredentialRepository.new(token: TOKEN, context: context_for([]))
    authenticator = build_authenticator(repository)

    assert_nil authenticator.authenticate(request_with(LEGACY_TOKEN))
  end

  def test_explicit_legacy_token_returns_only_the_supplied_migration_context
    scoped_context = context_for(["personal-threads"])
    legacy_context = context_for(%w[personal-instagram personal-threads])
    repository = FakeCredentialRepository.new(token: TOKEN, context: scoped_context)
    authenticator = PrismHub::Interfaces::Http::Authenticator.new(
      credential_repository: repository,
      clock: -> { NOW },
      legacy_token: LEGACY_TOKEN,
      legacy_context: legacy_context
    )

    assert_same legacy_context, authenticator.authenticate(request_with(LEGACY_TOKEN))
    assert_same scoped_context, authenticator.authenticate(request_with(TOKEN))
  end

  private

  def build_authenticator(repository)
    PrismHub::Interfaces::Http::Authenticator.new(
      credential_repository: repository,
      clock: -> { NOW }
    )
  end

  def request_with(token)
    Rack::Request.new("HTTP_AUTHORIZATION" => "Bearer #{token}")
  end

  def context_for(channels)
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-personal",
      capabilities: PrismHub::Domain::Capabilities::ALL,
      allowed_channel_ids: channels
    )
  end
end
