# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class HttpAisKeySourceTest < Minitest::Test
  ISSUER = "https://auth.aiaiaiai.org".freeze
  NOW = 1_800_000_000

  def setup
    @first = OpenSSL::PKey.generate_key("ED25519")
    @second = OpenSSL::PKey.generate_key("ED25519")
    @fetches = []
    @documents = [jwks("k1" => @first)]
    @source = PrismHub::Adapters::HttpAisKeySource.new(
      issuer: ISSUER,
      fetch: lambda { |uri|
        @fetches << uri.to_s
        document = @documents.first
        raise document if document.is_a?(Exception)

        document
      }
    )
  end

  def test_reads_ais_published_keys_once_and_caches_them
    assert_equal @first.raw_public_key, @source.key(kid: "k1", now: NOW).raw_public_key
    assert_equal @first.raw_public_key, @source.key(kid: "k1", now: NOW + 10).raw_public_key
    assert_equal ["#{ISSUER}/.well-known/jwks.json"], @fetches
  end

  def test_an_unknown_key_id_refreshes_at_most_once_a_minute
    @source.key(kid: "k1", now: NOW)
    @documents = [jwks("k1" => @first, "k2" => @second)]

    assert_nil @source.key(kid: "k2", now: NOW + 5)
    assert_nil @source.key(kid: "made-up", now: NOW + 6)
    assert_equal 1, @fetches.length

    assert_equal @second.raw_public_key, @source.key(kid: "k2", now: NOW + 61).raw_public_key
    assert_equal 2, @fetches.length
  end

  def test_an_unreachable_ais_keeps_the_keys_already_known
    @source.key(kid: "k1", now: NOW)
    @documents = [RuntimeError.new("down")]

    assert_equal @first.raw_public_key, @source.key(kid: "k1", now: NOW + 600).raw_public_key
  end

  def test_entries_that_are_not_ed25519_keys_are_ignored
    @documents = [JSON.generate("keys" => [
      {"kty" => "RSA", "kid" => "rsa", "n" => "x", "e" => "AQAB"},
      {"kty" => "OKP", "crv" => "Ed25519", "kid" => "short", "x" => "AAAA"},
      {"kty" => "OKP", "crv" => "Ed25519", "kid" => "k1", "x" => raw(@first)}
    ])]

    assert_nil @source.key(kid: "rsa", now: NOW)
    assert_nil @source.key(kid: "short", now: NOW + 61)
    refute_nil @source.key(kid: "k1", now: NOW + 122)
  end

  private

  def raw(key)
    Base64.urlsafe_encode64(key.raw_public_key, padding: false)
  end

  def jwks(keys)
    JSON.generate(
      "keys" => keys.map do |kid, key|
        {"kty" => "OKP", "crv" => "Ed25519", "use" => "sig", "alg" => "EdDSA", "kid" => kid, "x" => raw(key)}
      end
    )
  end
end
