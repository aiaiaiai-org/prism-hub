# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class SocialAccountAccess
      ROLES = %w[owner manager publisher].freeze
      STATUSES = %w[active revoked].freeze

      attr_reader :id, :user_identity, :social_account, :role, :status, :revoked_at

      def initialize(id:, user_identity:, social_account:, role:, status:, revoked_at: nil)
        unless user_identity.is_a?(UserIdentity)
          raise InputError.new(
            "hub.social_account_access.user_identity.invalid",
            "social account access must reference a user identity"
          )
        end
        unless social_account.is_a?(SocialAccount)
          raise InputError.new(
            "hub.social_account_access.social_account.invalid",
            "social account access must reference a social account"
          )
        end

        @id = reference(id)
        @user_identity = user_identity
        @social_account = social_account
        @role = enum(role, ROLES, "role")
        @status = enum(status, STATUSES, "status")
        @revoked_at = revoked_time(revoked_at)
        validate_state!
        freeze
      end

      def active?
        status == "active"
      end

      def owner?
        role == "owner"
      end

      def can_publish?
        active? && %w[owner manager publisher].include?(role)
      end

      private

      def reference(value)
        string = String(value)
        return string.freeze unless string.empty?

        raise InputError.new(
          "hub.social_account_access.id.invalid",
          "id must be a non-empty reference"
        )
      end

      def enum(value, allowed, field)
        string = String(value)
        return string.freeze if allowed.include?(string)

        raise InputError.new(
          "hub.social_account_access.#{field}.invalid",
          "social account access #{field} is invalid"
        )
      end

      def revoked_time(value)
        return nil if value.nil?
        return value.utc.freeze if value.is_a?(Time)

        raise InputError.new(
          "hub.social_account_access.revoked_at.invalid",
          "revoked_at must be a Time"
        )
      end

      def validate_state!
        coherent = (status == "active" && revoked_at.nil?) ||
          (status == "revoked" && revoked_at)
        return if coherent

        raise InputError.new(
          "hub.social_account_access.state.invalid",
          "social account access status and revoked_at are inconsistent"
        )
      end
    end
  end
end
