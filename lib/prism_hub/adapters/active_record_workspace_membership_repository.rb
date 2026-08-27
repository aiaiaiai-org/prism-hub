# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordWorkspaceMembershipRepository < Ports::WorkspaceMembershipRepository
      STATUS_ACTIVE = "active".freeze
      STATUS_REVOKED = "revoked".freeze
      ROLE_OWNER = "owner".freeze

      def grant(user_identity:, workspace_id:, role:)
        validate_user_identity!(user_identity)
        workspace_ref = reference(workspace_id, "workspace_id")
        role_ref = normalize_role(role)

        ::ActiveRecord::Base.transaction do
          workspace = locked_active_workspace!(workspace_ref)
          identity = locked_active_identity!(user_identity)
          existing = ActiveRecordRecords::WorkspaceMembership.lock.find_by(
            workspace: workspace,
            user_identity: identity
          )
          return verify_existing!(existing, role_ref) if existing

          to_domain(
            ActiveRecordRecords::WorkspaceMembership.create!(
              workspace: workspace,
              user_identity: identity,
              role: role_ref,
              status: STATUS_ACTIVE
            )
          )
        end
      rescue ::ActiveRecord::RecordNotUnique
        verify_concurrent_grant!(user_identity, workspace_ref, role_ref)
      end

      def find(user_identity_id:, workspace_id:)
        workspace_ref = reference(workspace_id, "workspace_id")
        identity_ref = reference(user_identity_id, "user_identity_id")
        record = membership_scope.joins(:workspace).find_by(
          workspaces: {identifier: workspace_ref},
          user_identity_id: identity_ref
        )
        record && to_domain(record)
      end

      def revoke(user_identity_id:, workspace_id:, revoked_at:)
        workspace_ref = reference(workspace_id, "workspace_id")
        identity_ref = reference(user_identity_id, "user_identity_id")
        timestamp = normalized_timestamp(revoked_at)

        ::ActiveRecord::Base.transaction do
          workspace = locked_workspace!(workspace_ref)
          record = ActiveRecordRecords::WorkspaceMembership.lock.find_by(
            workspace: workspace,
            user_identity_id: identity_ref
          )
          unless record
            raise WorkspaceMembershipNotFoundError.new(
              "hub.workspace_membership.not_found",
              "workspace membership was not found"
            )
          end

          if record.status == STATUS_ACTIVE
            ensure_not_last_owner!(record)
            record.update!(status: STATUS_REVOKED, revoked_at: timestamp)
          end
          to_domain(record)
        end
      end

      private

      def membership_scope
        ActiveRecordRecords::WorkspaceMembership.includes(:workspace, :user_identity)
      end

      def validate_user_identity!(user_identity)
        return if user_identity.is_a?(Domain::UserIdentity)

        raise ArgumentError, "user_identity must be a UserIdentity"
      end

      def normalize_role(role)
        string = String(role)
        return string if Domain::WorkspaceMembership::ROLES.include?(string)

        raise ArgumentError, "role is not supported"
      end

      def locked_active_workspace!(workspace_id)
        workspace = locked_workspace!(workspace_id)
        return workspace if workspace.status == STATUS_ACTIVE

        raise WorkspaceMembershipConflictError.new(
          "hub.workspace.disabled",
          "disabled workspaces cannot receive memberships"
        )
      end

      def locked_workspace!(workspace_id)
        workspace = ActiveRecordRecords::Workspace.lock.find_by(identifier: workspace_id)
        return workspace if workspace

        raise WorkspaceNotFoundError.new(
          "hub.workspace.not_found",
          "workspace was not found"
        )
      end

      def locked_active_identity!(user_identity)
        record = ActiveRecordRecords::UserIdentity.lock.find_by(id: user_identity.id)
        unless record
          raise UserIdentityNotFoundError.new(
            "hub.user_identity.not_found",
            "user identity was not found"
          )
        end

        canonical = user_identity.canonical_identity
        coherent = record.canonical_type == canonical.type && record.canonical_id == canonical.id
        unless coherent
          raise WorkspaceMembershipConflictError.new(
            "hub.workspace_membership.identity_mismatch",
            "user identity does not match persisted canonical identity"
          )
        end
        if record.status != STATUS_ACTIVE || !user_identity.active?
          raise UserIdentityConflictError.new(
            "hub.user_identity.disabled",
            "disabled user identities cannot receive workspace memberships"
          )
        end

        record
      end

      def verify_existing!(record, role)
        if record.status == STATUS_REVOKED
          raise WorkspaceMembershipConflictError.new(
            "hub.workspace_membership.revoked",
            "revoked memberships require an explicit reactivation operation"
          )
        end
        if record.role != role
          raise WorkspaceMembershipConflictError.new(
            "hub.workspace_membership.role_mismatch",
            "workspace membership role differs; change roles through an explicit role operation"
          )
        end

        to_domain(record)
      end

      def verify_concurrent_grant!(user_identity, workspace_id, role)
        workspace = ActiveRecordRecords::Workspace.find_by(identifier: workspace_id)
        record = workspace && ActiveRecordRecords::WorkspaceMembership.find_by(
          workspace: workspace,
          user_identity_id: user_identity.id
        )
        unless record
          raise WorkspaceMembershipConflictError.new(
            "hub.workspace_membership.conflict",
            "workspace membership could not be granted"
          )
        end

        locked_active_identity!(user_identity)
        verify_existing!(record, role)
      end

      def ensure_not_last_owner!(record)
        return unless record.role == ROLE_OWNER

        other_owner_exists = ActiveRecordRecords::WorkspaceMembership.where(
          workspace_id: record.workspace_id,
          role: ROLE_OWNER,
          status: STATUS_ACTIVE
        ).where.not(id: record.id).exists?
        return if other_owner_exists

        raise WorkspaceMembershipConflictError.new(
          "hub.workspace_membership.last_owner",
          "the last active workspace owner cannot be revoked"
        )
      end

      def normalized_timestamp(value)
        return value.utc if value.is_a?(Time)

        raise ArgumentError, "revoked_at must be a Time"
      end

      def reference(value, field)
        string = String(value)
        return string if Domain::Channel::REFERENCE_PATTERN.match?(string)

        raise ArgumentError, "#{field} must be a non-empty stable reference"
      end

      def to_domain(record)
        identity = record.user_identity
        Domain::WorkspaceMembership.new(
          id: record.id,
          workspace_id: record.workspace.identifier,
          user_identity: Domain::UserIdentity.new(
            id: identity.id,
            canonical_identity: Domain::CanonicalIdentityRef.new(
              type: identity.canonical_type,
              id: identity.canonical_id
            ),
            status: identity.status
          ),
          role: record.role,
          status: record.status,
          revoked_at: record.revoked_at&.to_time&.utc
        )
      end
    end
  end
end
