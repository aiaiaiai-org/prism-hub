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

  class FakeProductTokenVerifier < PrismHub::Ports::ProductTokenVerifier
    def verify(token:, now:)
      token == "header.payload.signature" ? "0xda-market" : nil
    end
  end

  class FakePrincipalRepository < PrismHub::Ports::ServicePrincipalRepository
    def initialize(context)
      @context = context
    end

    def authorise_product(product_id:)
      product_id == "0xda-market" ? @context : nil
    end
  end

  def test_an_ais_product_token_resolves_to_the_products_hub_grants
    product_context = context_for(["personal-threads"])
    repository = FakeCredentialRepository.new(token: TOKEN, context: context_for([]))
    authenticator = PrismHub::Interfaces::Http::Authenticator.new(
      credential_repository: repository,
      clock: -> { NOW },
      product_token_verifier: FakeProductTokenVerifier.new,
      principal_repository: FakePrincipalRepository.new(product_context)
    )

    assert_same product_context, authenticator.authenticate(request_with("header.payload.signature"))
    assert_nil authenticator.authenticate(request_with("header.payload.forged"))
    refute_nil authenticator.authenticate(request_with(TOKEN))
  end

  def test_a_token_ais_does_not_vouch_for_falls_through_to_the_other_credentials
    legacy_context = context_for(["personal-threads"])
    dotted_legacy_token = "legacy.token.that-is-longer-than-thirty-two-characters"
    authenticator = PrismHub::Interfaces::Http::Authenticator.new(
      credential_repository: FakeCredentialRepository.new(token: TOKEN, context: context_for([])),
      clock: -> { NOW },
      legacy_token: dotted_legacy_token,
      legacy_context: legacy_context,
      product_token_verifier: FakeProductTokenVerifier.new,
      principal_repository: FakePrincipalRepository.new(context_for([]))
    )

    assert_same legacy_context, authenticator.authenticate(request_with(dotted_legacy_token))
  end

  def test_a_jwt_is_not_a_credential_while_product_tokens_are_off
    repository = FakeCredentialRepository.new(token: TOKEN, context: context_for([]))
    authenticator = build_authenticator(repository)

    assert_nil authenticator.authenticate(request_with("header.payload.signature"))
  end

  def test_product_authentication_needs_both_parts
    error = assert_raises(PrismHub::ConfigurationError) do
      PrismHub::Interfaces::Http::Authenticator.new(
        credential_repository: FakeCredentialRepository.new(token: TOKEN, context: context_for([])),
        clock: -> { NOW },
        product_token_verifier: FakeProductTokenVerifier.new
      )
    end
    assert_equal "hub.product_auth.incomplete", error.code
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
