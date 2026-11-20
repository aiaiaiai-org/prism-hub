# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class AisEnvironmentTest < Minitest::Test
  SETTING = "PRISM_HUB_DEVELOPMENT_AIS_ISSUER".freeze
  DECLARED = "PRISM_HUB_AIS_ENVIRONMENT".freeze
  PRODUCTION = "https://auth.aiaiaiai.org".freeze
  DEVELOPMENT = "https://ais-dev.example".freeze
  NOW = Time.utc(2026, 11, 20, 7, 0, 0)

  def test_production_pins_its_issuer
    assert_equal PRODUCTION, issuer({"RAILS_ENV" => "production"})
    assert_equal PRODUCTION, issuer({"RACK_ENV" => "production"})
    assert_equal PRODUCTION, issuer({"RAILS_ENV" => "development", DECLARED => "production"})
    assert_raises(PrismHub::ConfigurationError) do
      issuer({"RAILS_ENV" => "production", SETTING => DEVELOPMENT})
    end
    assert_raises(PrismHub::ConfigurationError) do
      issuer({"RAILS_ENV" => "production", DECLARED => "production", SETTING => DEVELOPMENT})
    end
  end

  def test_local_development_never_falls_back_to_production
    assert_nil issuer({})
    %w[development test].each do |environment|
      assert_nil issuer({"RAILS_ENV" => environment})
      assert_equal DEVELOPMENT, issuer({"RAILS_ENV" => environment, SETTING => DEVELOPMENT})
    end
  end

  # The shipped image is RAILS_ENV=production for every workload, development included.
  def test_a_development_hub_on_the_production_image_declares_its_trust_environment
    image = {"RAILS_ENV" => "production", DECLARED => "development"}
    assert_equal DEVELOPMENT, issuer(image.merge(SETTING => DEVELOPMENT))
    assert_nil issuer(image), "a missing development origin accepts no AIS token, not production"
    assert_nil issuer(image.merge(SETTING => ""))
  end

  def test_an_unknown_or_malformed_declaration_stops_startup
    ["Production", "prod", "staging", " development", "development "].each do |declared|
      assert_raises(PrismHub::ConfigurationError, declared) do
        issuer({"RAILS_ENV" => "production", DECLARED => declared})
      end
    end
    assert_raises(PrismHub::ConfigurationError) { issuer({"RAILS_ENV" => "staging"}) }
  end

  def test_refuses_production_and_noncanonical_origins
    %w[
      https://auth.aiaiaiai.org
      https://www.auth.aiaiaiai.org
      https://AUTH.aiaiaiai.org
      https://auth.aiaiaiai.org.
      https://ais-dev.example/path
      https://ais-dev.example?query
      https://ais-dev.example@auth.aiaiaiai.org
      http://ais-dev.example
    ].each do |origin|
      assert_raises(PrismHub::ConfigurationError, origin) do
        issuer({"RAILS_ENV" => "production", DECLARED => "development", SETTING => origin})
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
