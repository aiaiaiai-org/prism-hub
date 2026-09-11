# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class ProviderTokenCipher
      PURPOSE = "prism-hub.provider-token.v1".freeze
      KEY_BYTES = 32

      def initialize(key_base64:)
        key = Base64.strict_decode64(String(key_base64))
        raise ArgumentError, "provider token key must decode to 32 bytes" unless key.bytesize == KEY_BYTES

        @encryptor = ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
      rescue ArgumentError => error
        raise ConfigurationError.new(
          "hub.provider_token_key.invalid",
          "PRISM_HUB_PROVIDER_TOKEN_KEY_BASE64 must be strict base64 for exactly 32 bytes",
          details: {"cause" => error.class.name}
        )
      end

      def encrypt(value)
        @encryptor.encrypt_and_sign(String(value), purpose: PURPOSE)
      end

      def decrypt(ciphertext)
        @encryptor.decrypt_and_verify(String(ciphertext), purpose: PURPOSE)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        raise CredentialConflictError.new(
          "hub.mail.credential.decrypt_failed",
          "stored mail credential cannot be decrypted"
        )
      end
    end
  end
end
