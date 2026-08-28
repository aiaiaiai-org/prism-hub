# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class SecurePublicUserIdGenerator
      ALPHABET = (("a".."z").to_a + ("0".."9").to_a).freeze
      SLUG_LENGTH = 20

      def call
        slug = Array.new(SLUG_LENGTH) { ALPHABET.fetch(SecureRandom.random_number(ALPHABET.length)) }.join
        Domain::PublicUserId.new("0x#{slug}").to_s
      end
    end
  end
end
