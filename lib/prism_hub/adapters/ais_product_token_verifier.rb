# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    # Verifies an AIS product token (hub.v1, aiaiaiai-org/4x-ais docs/hub-protocol.md): an
    # `at+jwt` EdDSA JWT that AIS signed for this Hub. Answers the product's AIS client id.
    #
    # Hub accepts only tokens a product asked for itself: one that names an actor (`act`) is a
    # relayed token, which only Hub itself requests from AIS, and is refused here.
    class AisProductTokenVerifier < Ports::ProductTokenVerifier
      MAX_TOKEN_BYTES = 4096
      PART_PATTERN = /\A[A-Za-z0-9_-]+\z/
      PRODUCT_ID_PATTERN = /\A[a-z0-9-]{1,64}\z/
      LEEWAY_SECONDS = 30
      REQUIRED_SCOPE = "hub.call".freeze

      def initialize(issuer:, audience:, key_source:)
        @issuer = String(issuer).freeze
        @audience = String(audience).freeze
        @key_source = key_source
      end

      def verify(token:, now:)
        string = String(token)
        return nil if string.bytesize > MAX_TOKEN_BYTES

        parts = string.split(".", -1)
        return nil unless parts.length == 3 && parts.all? { |part| PART_PATTERN.match?(part) }

        header = decode_json(parts[0])
        return nil unless header.is_a?(Hash)
        return nil unless header["alg"] == "EdDSA" && header["typ"] == "at+jwt"

        seconds = now.to_i
        key = header["kid"].is_a?(String) ? @key_source.key(kid: header["kid"], now: seconds) : nil
        return nil unless key
        return nil unless signature_valid?(key, parts)

        claims = decode_json(parts[1])
        return nil unless claims.is_a?(Hash)

        product_id_from(claims, seconds)
      end

      private

      def product_id_from(claims, now)
        product_id = claims["sub"]
        return nil unless product_id.is_a?(String) && PRODUCT_ID_PATTERN.match?(product_id)
        return nil unless claims["iss"] == @issuer
        return nil unless audience_matches?(claims["aud"])
        return nil if claims.key?("client_id") && claims["client_id"] != product_id
        return nil if claims.key?("act")
        return nil unless claims["exp"].is_a?(Integer) && claims["exp"] > now
        return nil if claims["iat"].is_a?(Integer) && claims["iat"] > now + LEEWAY_SECONDS
        return nil unless claims["scope"].is_a?(String) && claims["scope"].split(" ").include?(REQUIRED_SCOPE)

        product_id
      end

      def audience_matches?(audience)
        case audience
        when String then audience == @audience
        when Array then audience.include?(@audience)
        else false
        end
      end

      def signature_valid?(key, parts)
        signature = Base64.urlsafe_decode64(parts[2])
        key.verify(nil, signature, "#{parts[0]}.#{parts[1]}")
      rescue ArgumentError, OpenSSL::PKey::PKeyError
        false
      end

      def decode_json(part)
        JSON.parse(Base64.urlsafe_decode64(part))
      rescue ArgumentError, JSON::ParserError
        nil
      end
    end
  end
end
