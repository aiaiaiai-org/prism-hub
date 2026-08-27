# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Http
      class Authenticator
        BEARER_PATTERN = /\ABearer ([^\s]+)\z/

        def initialize(credential_repository:, clock:, legacy_token: nil, legacy_context: nil)
          @credential_repository = credential_repository
          @clock = clock
          configure_legacy(legacy_token, legacy_context)
        end

        def authenticate(request)
          match = BEARER_PATTERN.match(request.get_header("HTTP_AUTHORIZATION").to_s)
          return nil unless match

          token = match[1]
          context = @credential_repository.authenticate(token: token, now: @clock.call)
          return context if context

          legacy_context_for(token)
        end

        private

        def configure_legacy(token, context)
          return if token.nil? && context.nil?

          if token.nil? || context.nil?
            raise ConfigurationError.new(
              "hub.legacy_auth.incomplete",
              "legacy bearer authentication requires both a token and authorisation context"
            )
          end
          unless token.is_a?(String) && token.length >= 32
            raise ConfigurationError.new(
              "hub.legacy_auth.token_invalid",
              "legacy Hub bearer token must contain at least 32 characters"
            )
          end

          @legacy_token_digest = Digest::SHA256.hexdigest(token).freeze
          @legacy_context = context
        end

        def legacy_context_for(token)
          return nil unless @legacy_token_digest

          candidate = Digest::SHA256.hexdigest(token)
          return nil unless Rack::Utils.secure_compare(candidate, @legacy_token_digest)

          @legacy_context
        end
      end
    end
  end
end
