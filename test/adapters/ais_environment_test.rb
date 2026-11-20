# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class AisEnvironmentTest < Minitest::Test
  SETTING = "PRISM_HUB_AIS_ISSUER".freeze
  PRODUCTION = "https://auth.aiaiaiai.org".freeze
  DEVELOPMENT = "https://ais-dev.example".freeze
  NOW = Time.utc(2026, 11, 20, 7, 0, 0)

  def test_without_the_setting_no_ais_token_is_accepted_whatever_the_rails_mode
    [{}, {"RAILS_ENV" => "production"}, {"RAILS_ENV" => "development"}, {"RAILS_ENV" => "test"}, {SETTING => ""}].each do |env|
      assert_nil issuer(env), env.inspect
    end
  end

  def test_the_setting_alone_names_the_trusted_origin_in_every_rails_mode
    [PRODUCTION, DEVELOPMENT].each do |origin|
      [{}, {"RAILS_ENV" => "production"}, {"RAILS_ENV" => "development"}].each do |mode|
        assert_equal origin, issuer(mode.merge(SETTING => origin))
      end
    end
  end

  def test_refuses_noncanonical_origins
    %w[
      https://AUTH.aiaiaiai.org
      https://auth.aiaiaiai.org.
      https://auth.aiaiaiai.org/path
      https://auth.aiaiaiai.org/
      https://auth.aiaiaiai.org?query
      https://auth.aiaiaiai.org:8443
      https://ais-dev.example@auth.aiaiaiai.org
      http://ais-dev.example
      ais-dev.example
      localhost
    ].each do |origin|
      assert_raises(PrismHub::ConfigurationError, origin) do
        issuer({"RAILS_ENV" => "production", SETTING => origin})
      end
    end
  end

  def test_issuer_and_keys_come_from_one_origin_and_never_cross
    production_key = OpenSSL::PKey.generate_key("ED25519")
    development_key = OpenSSL::PKey.generate_key("ED25519")
    fetched = []
    key_source = PrismHub::Adapters::HttpAisKeySource.new(
      issuer: DEVELOPMENT,
      fetch: ->(uri) { fetched << uri.to_s; JSON.generate("keys" => [jwk(development_key)]) }
    )
    development = verifier(DEVELOPMENT, key_source)
    production = verifier(PRODUCTION, FixedKeys.new("ais-1" => public_only(production_key)))

    assert_equal "0xda-market", development.verify(token: token(DEVELOPMENT, development_key), now: NOW)
    assert_equal ["#{DEVELOPMENT}/.well-known/jwks.json"], fetched

    # Neither environment accepts the other's issuer, even signed by its own key.
    assert_nil development.verify(token: token(PRODUCTION, development_key), now: NOW)
    assert_nil production.verify(token: token(DEVELOPMENT, production_key), now: NOW)
    # And neither accepts the other's signing key under its own issuer.
    assert_nil development.verify(token: token(DEVELOPMENT, production_key), now: NOW)
    assert_nil production.verify(token: token(PRODUCTION, development_key), now: NOW)
  end

  private

  class FixedKeys < PrismHub::Ports::AisKeySource
    def initialize(keys)
      @keys = keys
    end

    def key(kid:, now:)
      @keys[kid]
    end
  end

  def issuer(env)
    PrismHub::Bootstrap.send(:product_issuer, env)
  end

  def verifier(issuer, key_source)
    PrismHub::Adapters::AisProductTokenVerifier.new(issuer: issuer, audience: "prism-hub", key_source: key_source)
  end

  def public_only(key)
    OpenSSL::PKey.new_raw_public_key("ED25519", key.raw_public_key)
  end

  def jwk(key)
    {"kty" => "OKP", "crv" => "Ed25519", "kid" => "ais-1", "x" => Base64.urlsafe_encode64(key.raw_public_key, padding: false)}
  end

  def token(issuer, key)
    claims = {
      "iss" => issuer, "sub" => "0xda-market", "client_id" => "0xda-market", "aud" => "prism-hub",
      "scope" => "hub.call", "iat" => NOW.to_i, "exp" => NOW.to_i + 300, "jti" => "token-1"
    }
    input = [{"alg" => "EdDSA", "typ" => "at+jwt", "kid" => "ais-1"}, claims]
      .map { |part| Base64.urlsafe_encode64(JSON.generate(part), padding: false) }.join(".")
    "#{input}.#{Base64.urlsafe_encode64(key.sign(nil, input), padding: false)}"
  end
end
