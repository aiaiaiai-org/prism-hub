# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class AisProductTokenVerifierTest < Minitest::Test
  ISSUER = "https://auth.aiaiaiai.org".freeze
  NOW = Time.utc(2026, 11, 12, 7, 0, 0)

  class FixedKeySource < PrismHub::Ports::AisKeySource
    def initialize(keys)
      @keys = keys
    end

    def key(kid:, now:)
      @keys[kid]
    end
  end

  def setup
    @ais_key = OpenSSL::PKey.generate_key("ED25519")
    @verifier = PrismHub::Adapters::AisProductTokenVerifier.new(
      issuer: ISSUER,
      audience: "prism-hub",
      key_source: FixedKeySource.new("ais-1" => public_only(@ais_key))
    )
  end

  def test_a_product_token_from_ais_names_the_product
    assert_equal "0xda-market", @verifier.verify(token: token, now: NOW)
  end

  def test_an_array_audience_naming_hub_is_accepted
    assert_equal "0xda-market", @verifier.verify(token: token(claims(aud: ["other", "prism-hub"])), now: NOW)
  end

  def test_a_token_ais_did_not_sign_is_refused
    other = OpenSSL::PKey.generate_key("ED25519")
    assert_nil @verifier.verify(token: token(claims, key: other), now: NOW)
    assert_nil @verifier.verify(token: token(claims, kid: "unknown"), now: NOW)
  end

  def test_a_token_with_its_claims_swapped_fails_its_signature
    genuine = token.split(".")
    forged = token(claims(sub: "0x1")).split(".")
    assert_nil @verifier.verify(token: [genuine[0], forged[1], genuine[2]].join("."), now: NOW)
  end

  def test_a_token_for_someone_else_or_out_of_time_is_refused
    [
      claims(iss: "https://elsewhere.example"),
      claims(aud: "0x1"),
      claims(exp: NOW.to_i),
      claims(exp: "later"),
      claims(iat: NOW.to_i + 3600),
      claims(sub: "Not A Product"),
      claims(client_id: "0x1"),
      claims(scope: "hub.events"),
      claims(scope: nil),
      claims(act: {"sub" => "0x1"})
    ].each do |bad|
      assert_nil @verifier.verify(token: token(bad), now: NOW), bad.inspect
    end
  end

  def test_only_an_eddsa_access_token_is_read
    assert_nil @verifier.verify(token: token(claims, typ: "JWT"), now: NOW)
    assert_nil @verifier.verify(token: token(claims, alg: "none"), now: NOW)
  end

  def test_malformed_input_is_refused_without_raising
    ["", "a.b", "a.b.c.d", "a+b.c.d", "#{'a' * 5000}.b.c", "e30.e30.AAAA"].each do |bad|
      assert_nil @verifier.verify(token: bad, now: NOW), bad
    end
  end

  private

  def public_only(key)
    OpenSSL::PKey.new_raw_public_key("ED25519", key.raw_public_key)
  end

  def claims(**overrides)
    {
      "iss" => ISSUER,
      "sub" => "0xda-market",
      "client_id" => "0xda-market",
      "aud" => "prism-hub",
      "scope" => "hub.call hub.events",
      "iat" => NOW.to_i,
      "exp" => NOW.to_i + 300,
      "jti" => "token-1"
    }.merge(overrides.transform_keys(&:to_s)).compact
  end

  def token(payload = claims, key: @ais_key, kid: "ais-1", typ: "at+jwt", alg: "EdDSA")
    header = {"alg" => alg, "typ" => typ, "kid" => kid}
    signing_input = [header, payload].map { |part| Base64.urlsafe_encode64(JSON.generate(part), padding: false) }.join(".")
    signature = key.sign(nil, signing_input)
    "#{signing_input}.#{Base64.urlsafe_encode64(signature, padding: false)}"
  end
end
