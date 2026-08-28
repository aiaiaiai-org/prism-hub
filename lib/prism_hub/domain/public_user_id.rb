# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class PublicUserId
      PREFIX = "0x".freeze
      MIN_SLUG_LENGTH = 2
      MAX_SLUG_LENGTH = 32
      SYMBOLS = [
        "-", "/", ":", ";", "(", ")", "₴", "&", "@", '"', ".", ",", "?", "!", "'",
        "[", "]", "{", "}", "#", "%", "^", "*", "+", "=", "_", "\\", "|", "~", "<",
        ">", "€", "$", "£", "•"
      ].freeze
      ALLOWED_CHARACTERS = (("a".."z").to_a + ("0".."9").to_a + SYMBOLS).freeze

      attr_reader :value

      def initialize(value)
        string = String(value)
        slug = string.delete_prefix(PREFIX)
        valid = string.start_with?(PREFIX) &&
          slug.length.between?(MIN_SLUG_LENGTH, MAX_SLUG_LENGTH) &&
          slug.each_char.all? { |character| ALLOWED_CHARACTERS.include?(character) }
        unless valid
          raise InputError.new(
            "hub.user_identity.public_id.invalid",
            "public user id must use the canonical 0x slug grammar"
          )
        end

        @value = string.freeze
        freeze
      end

      def to_s
        value
      end
    end
  end
end
