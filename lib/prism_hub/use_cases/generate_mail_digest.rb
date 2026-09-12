# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class GenerateMailDigest
      def initialize(
        execution_gateway:,
        credential_resolver: nil,
        credential_repository: nil,
        oauth_gateway: nil,
        provider: nil,
        origin: nil,
        resource: nil,
        clock: -> { Time.now.utc },
        refresh_before_seconds: ResolveMailCredential::REFRESH_BEFORE_SECONDS
      )
        @execution_gateway = execution_gateway
        @credential_resolver = credential_resolver || ResolveMailCredential.new(
          credential_repository: credential_repository,
          oauth_gateway: oauth_gateway,
          provider: provider,
          origin: origin,
          resource: resource,
          clock: clock,
          refresh_before_seconds: refresh_before_seconds
        )
      end

      def call(mailbox_id:, since:, before:)
        mailbox_id = validate_mailbox_id(mailbox_id)
        since_time = parse_timestamp(since, "since")
        before_time = parse_timestamp(before, "before")
        unless since_time < before_time
          raise InputError.new("hub.mail.window.invalid", "mail digest since must precede before")
        end

        credential = @credential_resolver.call
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
