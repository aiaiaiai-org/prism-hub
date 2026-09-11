# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class GenerateMailDigest
      READ_SCOPE = "mail:read".freeze

      def initialize(credential_repository:, execution_gateway:, provider:, origin:, resource:, clock: -> { Time.now.utc })
        @credential_repository = credential_repository
        @execution_gateway = execution_gateway
        @provider = String(provider)
        @origin = String(origin)
        @resource = String(resource)
        @clock = clock
      end

      def call(mailbox_id:, since:, before:)
        mailbox_id = validate_mailbox_id(mailbox_id)
        since_time = parse_timestamp(since, "since")
        before_time = parse_timestamp(before, "before")
        unless since_time < before_time
          raise InputError.new("hub.mail.window.invalid", "mail digest since must precede before")
        end

        credential = @credential_repository.fetch(
          provider: @provider,
          origin: @origin,
          resource: @resource
        )
        unless credential
          raise CredentialNotFoundError.new(
            "hub.mail.credential.not_found",
            "no active HQBase mail credential is connected"
          )
        end

        unless credential.scope.include?(READ_SCOPE)
          raise AuthorisationError.new(
            "hub.mail.credential.scope_missing",
            "connected HQBase credential does not grant mail:read"
          )
        end

        unless credential.token_type.casecmp?("Bearer")
          raise AuthorisationError.new(
            "hub.mail.credential.token_type_invalid",
            "connected HQBase credential is not a Bearer token"
          )
        end

        if credential.expires_at && credential.expires_at <= @clock.call
          raise AuthorisationError.new(
            "hub.mail.credential.expired",
            "connected HQBase access token has expired and must be refreshed or reconnected"
          )
        end

        @execution_gateway.execute(
          mailbox_id: mailbox_id,
          since: since_time.iso8601,
          before: before_time.iso8601,
          access_token: credential.access_token
        )
      end

      private

      def validate_mailbox_id(value)
        unless value.is_a?(String) && value.match?(/\A[^[:cntrl:]\s]{1,100}\z/)
          raise InputError.new("hub.mail.mailbox_id.invalid", "mailbox_id must be a nonblank identifier")
        end

        value
      end

      def parse_timestamp(value, label)
        unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
          raise InputError.new("hub.mail.window.invalid", "#{label} must be ISO 8601 with an explicit UTC offset")
        end

        Time.iso8601(value).utc
      rescue ArgumentError
        raise InputError.new("hub.mail.window.invalid", "#{label} must be a valid ISO 8601 timestamp")
      end
    end
  end
end
