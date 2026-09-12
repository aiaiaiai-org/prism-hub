# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ResolveMailCredential
      READ_SCOPE = "mail:read".freeze
      REFRESH_BEFORE_SECONDS = 60

      def initialize(
        credential_repository:,
        oauth_gateway:,
        provider:,
        origin:,
        resource:,
        clock: -> { Time.now.utc },
        refresh_before_seconds: REFRESH_BEFORE_SECONDS
      )
        @credential_repository = credential_repository
        @oauth_gateway = oauth_gateway
        @provider = String(provider)
        @origin = String(origin)
        @resource = String(resource)
        @clock = clock
        @refresh_before_seconds = Integer(refresh_before_seconds)
        raise ArgumentError if @refresh_before_seconds.negative?
      end

      def call
        credential = fetch_credential!
        validate_credential!(credential)
        refresh_if_needed(credential)
      end

      private

      def fetch_credential!
        credential = @credential_repository.fetch(**credential_identity)
        return credential if credential

        raise CredentialNotFoundError.new(
          "hub.mail.credential.not_found",
          "no active HQBase mail credential is connected"
        )
      end

      def credential_identity
        {provider: @provider, origin: @origin, resource: @resource}
      end

      def validate_credential!(credential)
        unless credential.scope.include?(READ_SCOPE)
          raise AuthorisationError.new(
            "hub.mail.credential.scope_missing",
            "connected HQBase credential does not grant mail:read"
          )
        end

        return credential if credential.token_type.casecmp?("Bearer")

        raise AuthorisationError.new(
          "hub.mail.credential.token_type_invalid",
          "connected HQBase credential is not a Bearer token"
        )
      end

      def refresh_if_needed(credential)
        return credential unless refresh_due?(credential)

        require_refresh_material!(credential)
        result = @oauth_gateway.refresh(
          client_id: credential.oauth_client_id,
          refresh_token: credential.refresh_token
        )

        case result.status
        when :refreshed
          persist_refresh!(credential, result)
        when :invalid_grant
          recover_concurrent_rotation_or_reconnect!(credential)
        else
          raise ExecutionUnavailableError.new(
            "hub.mail.oauth.refresh_failed",
            "HQBase OAuth token refresh failed",
            details: {"provider_error" => result.error}
          )
        end
      end

      def refresh_due?(credential)
        credential.expires_at && credential.expires_at <= (@clock.call + @refresh_before_seconds)
      end

      def require_refresh_material!(credential)
        return if nonempty?(credential.oauth_client_id) && nonempty?(credential.refresh_token)

        raise AuthorisationError.new(
          "hub.mail.credential.reconnect_required",
          "HQBase mail credential cannot be refreshed and must be reconnected"
        )
      end

      def persist_refresh!(credential, result)
        validate_refreshed_token!(result)
        expires_at = (@clock.call + result.expires_in).utc
        @credential_repository.store(
          **credential_identity,
          oauth_client_id: credential.oauth_client_id,
          access_token: result.access_token,
          refresh_token: result.refresh_token,
          scope: result.scope,
          token_type: result.token_type,
          expires_at: expires_at
        )

        refreshed = fetch_credential!
        validate_credential!(refreshed)
        refreshed
      end

      def validate_refreshed_token!(result)
        return if result.scope.include?(READ_SCOPE) && result.token_type.casecmp?("Bearer")

        raise AuthorisationError.new(
          "hub.mail.oauth.refresh_scope_invalid",
          "HQBase OAuth refresh did not preserve the required mail authorization"
        )
      end

      def recover_concurrent_rotation_or_reconnect!(stale_credential)
        current = @credential_repository.fetch(**credential_identity)
        if current && current.refresh_token != stale_credential.refresh_token
          validate_credential!(current)
          return current unless refresh_due?(current)
        end

        raise AuthorisationError.new(
          "hub.mail.credential.reconnect_required",
          "HQBase refresh token is no longer valid; reconnect mail authorization"
        )
      end

      def nonempty?(value)
        value.is_a?(String) && !value.empty?
      end
    end
  end
end
