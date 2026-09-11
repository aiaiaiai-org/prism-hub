# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class ConnectHqbaseMail
      def initialize(gateway:, credential_repository:, clock: -> { Time.now.utc }, sleeper: ->(seconds) { sleep(seconds) })
        @gateway = gateway
        @credential_repository = credential_repository
        @clock = clock
        @sleeper = sleeper
      end

      def start
        authorization = @gateway.start
        {
          "client_id" => authorization.client_id,
          "device_code" => authorization.device_code,
          "user_code" => authorization.user_code,
          "verification_uri" => authorization.verification_uri,
          "verification_uri_complete" => authorization.verification_uri_complete,
          "expires_at" => (@clock.call + authorization.expires_in).utc,
          "interval_seconds" => authorization.interval
        }
      end

      def complete(authorization:)
        deadline = authorization.fetch("expires_at")
        interval = Integer(authorization.fetch("interval_seconds"), 10)

        loop do
          raise_expired! if @clock.call >= deadline

          result = @gateway.poll(
            client_id: authorization.fetch("client_id"),
            device_code: authorization.fetch("device_code")
          )
          case result.status
          when :connected
            expires_at = result.expires_in && (@clock.call + result.expires_in).utc
            @credential_repository.store(
              provider: "hqbase",
              origin: @gateway.origin,
              resource: @gateway.resource,
              access_token: result.access_token,
              refresh_token: result.refresh_token,
              scope: result.scope,
              token_type: result.token_type,
              expires_at: expires_at
            )
            return {"status" => "connected", "expires_at" => expires_at}
          when :pending
            interval += 5 if result.error == "slow_down"
            @sleeper.call(interval)
          when :denied
            raise AuthorisationError.new("hub.mail.oauth.access_denied", "HQBase mail access was denied")
          when :expired
            raise_expired!
          else
            raise ExecutionUnavailableError.new(
              "hub.mail.oauth.failed",
              "HQBase OAuth authorization failed",
              details: {"provider_error" => result.error}
            )
          end
        end
      end

      private

      def raise_expired!
        raise AuthorisationError.new(
          "hub.mail.oauth.expired",
          "HQBase device authorization expired before approval"
        )
      end
    end
  end
end
