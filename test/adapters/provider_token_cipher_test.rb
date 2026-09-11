# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class ProviderTokenCipherTest < Minitest::Test
  def test_round_trips_without_plaintext_in_ciphertext
    key = Base64.strict_encode64("k" * 32)
    cipher = PrismHub::Adapters::ProviderTokenCipher.new(key_base64: key)

    ciphertext = cipher.encrypt("hqb_access_secret")

    refute_includes ciphertext, "hqb_access_secret"
    assert_equal "hqb_access_secret", cipher.decrypt(ciphertext)
  end

  def test_rejects_invalid_key_material
    error = assert_raises(PrismHub::ConfigurationError) do
      PrismHub::Adapters::ProviderTokenCipher.new(key_base64: Base64.strict_encode64("short"))
    end

    assert_equal "hub.provider_token_key.invalid", error.code
  end
end
