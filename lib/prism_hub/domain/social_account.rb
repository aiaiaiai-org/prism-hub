# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class SocialAccount
      PROVIDER_PATTERN = /\A[a-z][a-z0-9._-]{0,63}\z/

      attr_reader :id, :provider, :provider_account_id, :username, :display_name

      def initialize(id:, provider:, provider_account_id:, username: nil, display_name: nil)
        @id = reference(id, "id")
        @provider = provider_name(provider)
        @provider_account_id = opaque_reference(provider_account_id, "provider_account_id", 512)
        @username = optional_metadata(username, "username", 255)
        @display_name = optional_metadata(display_name, "display_name", 255)
        freeze
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze unless string.empty?

        raise InputError.new(
          "hub.social_account.#{field}.invalid",
          "#{field} must be a non-empty reference"
        )
      end

      def provider_name(value)
        string = String(value)
        return string.freeze if PROVIDER_PATTERN.match?(string)

        raise InputError.new(
          "hub.social_account.provider.invalid",
          "provider must use the canonical provider-name grammar"
        )
      end

      def opaque_reference(value, field, limit)
        string = String(value)
        return string.freeze if !string.empty? && string.length <= limit

        raise InputError.new(
          "hub.social_account.#{field}.invalid",
          "#{field} must be non-empty opaque provider data"
        )
      end

      def optional_metadata(value, field, limit)
        return nil if value.nil?

        string = String(value)
        return string.freeze if !string.empty? && string.length <= limit

        raise InputError.new(
          "hub.social_account.#{field}.invalid",
          "#{field} must be nil or non-empty display metadata"
        )
      end
    end
  end
end
