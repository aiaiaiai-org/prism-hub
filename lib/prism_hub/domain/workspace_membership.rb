# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class WorkspaceMembership
      ROLES = %w[owner admin member].freeze
      STATUSES = %w[active revoked].freeze

      attr_reader :id, :workspace_id, :user_identity, :role, :status, :revoked_at

      def initialize(id:, workspace_id:, user_identity:, role:, status:, revoked_at: nil)
        unless user_identity.is_a?(UserIdentity)
          raise InputError.new(
            "hub.workspace_membership.user_identity.invalid",
            "workspace membership must reference a user identity"
          )
        end

        @id = reference(id, "id")
        @workspace_id = reference(workspace_id, "workspace_id")
        @user_identity = user_identity
        @role = normalize_role(role)
        @status = normalize_status(status)
        @revoked_at = normalize_revoked_at(revoked_at)
        validate_state!
        freeze
      end

      def active?
        status == "active"
      end

      def owner?
        role == "owner"
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze if Channel::REFERENCE_PATTERN.match?(string)

        raise InputError.new(
          "hub.workspace_membership.#{field}.invalid",
          "#{field} must be a non-empty stable reference"
        )
      end

      def normalize_role(value)
        string = String(value)
        return string.freeze if ROLES.include?(string)

        raise InputError.new(
          "hub.workspace_membership.role.invalid",
          "workspace membership role is invalid"
        )
      end

      def normalize_status(value)
        string = String(value)
        return string.freeze if STATUSES.include?(string)

        raise InputError.new(
          "hub.workspace_membership.status.invalid",
          "workspace membership status is invalid"
        )
      end

      def normalize_revoked_at(value)
        return nil if value.nil?
        return value.utc.freeze if value.is_a?(Time)

        raise InputError.new(
          "hub.workspace_membership.revoked_at.invalid",
          "revoked_at must be a Time"
        )
      end

      def validate_state!
        coherent = (status == "active" && revoked_at.nil?) ||
          (status == "revoked" && revoked_at)
        return if coherent

        raise InputError.new(
          "hub.workspace_membership.state.invalid",
          "workspace membership status and revoked_at are inconsistent"
        )
      end
    end
  end
end
