# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class Authenticator
        BEARER_PATTERN = /\ABearer ([^\s]+)\z/

        def initialize(token:)
          unless token.is_a?(String) && token.length >= 32
            raise ConfigurationError.new(
              "hub.api_token.invalid",
              "PRISM_HUB_API_TOKEN must contain at least 32 characters"
            )
          end

          @token_digest = Digest::SHA256.hexdigest(token).freeze
        end

        def authorized?(request)
          match = BEARER_PATTERN.match(request.get_header("HTTP_AUTHORIZATION").to_s)
          return false unless match

          candidate = Digest::SHA256.hexdigest(match[1])
          Rack::Utils.secure_compare(candidate, @token_digest)
        end
      end
    end
  end
end
