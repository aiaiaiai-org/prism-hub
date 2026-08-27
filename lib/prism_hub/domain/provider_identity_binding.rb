# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class ProviderIdentityBinding
      STATUSES = %w[active revoked].freeze

      attr_reader :id, :user_identity, :provider_subject, :status, :revoked_at

      def initialize(id:, user_identity:, provider_subject:, status:, revoked_at: nil)
        unless user_identity.is_a?(UserIdentity)
          raise InputError.new(
            "hub.provider_identity_binding.user_identity.invalid",
            "provider identity bindings require a UserIdentity"
          )
        end
        unless provider_subject.is_a?(ProviderSubject)
          raise InputError.new(
            "hub.provider_identity_binding.provider_subject.invalid",
            "provider identity bindings require a ProviderSubject"
          )
        end

        @id = reference(id)
        @user_identity = user_identity
        @provider_subject = provider_subject
        @status = normalized_status(status)
        @revoked_at = normalized_revoked_at(revoked_at)
        validate_status_timestamp!
        freeze
      end

      def active?
        status == "active"
      end

      def revoked?
        status == "revoked"
      end

      private

      def reference(value)
        string = String(value)
        return string.freeze unless string.empty?

        raise InputError.new(
          "hub.provider_identity_binding.id.invalid",
          "id must be a non-empty reference"
        )
      end

      def normalized_status(value)
        string = String(value)
        return string.freeze if STATUSES.include?(string)

        raise InputError.new(
          "hub.provider_identity_binding.status.invalid",
          "provider identity binding status is invalid"
        )
      end

      def normalized_revoked_at(value)
        return nil if value.nil?
        return value.utc.freeze if value.is_a?(Time)

        raise InputError.new(
          "hub.provider_identity_binding.revoked_at.invalid",
          "revoked_at must be a Time"
        )
      end

      def validate_status_timestamp!
        coherent = (active? && revoked_at.nil?) || (revoked? && !revoked_at.nil?)
        return if coherent

        raise InputError.new(
          "hub.provider_identity_binding.state.invalid",
          "binding status and revoked_at must describe the same state"
        )
      end
    end
  end
end
