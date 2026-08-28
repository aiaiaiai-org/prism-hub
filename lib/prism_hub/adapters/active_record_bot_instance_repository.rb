# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordBotInstanceRepository < Ports::BotInstanceRepository
      STATUS_ACTIVE = "active".freeze
      STATUS_PAUSED = "paused".freeze
      STATUS_DISABLED = "disabled".freeze
      ROLE_OWNER = "owner".freeze

      def ensure(principal_id:, workspace_id:, actor_user_identity_id:, occurred_at:)
        principal_ref = reference(principal_id, "principal_id")
        workspace_ref = reference(workspace_id, "workspace_id")
        actor_ref = reference(actor_user_identity_id, "actor_user_identity_id")
        timestamp = normalized_timestamp(occurred_at)

        ::ActiveRecord::Base.transaction do
          principal, workspace, actor = locked_context!(principal_ref, workspace_ref, actor_ref)
          record = locked_instance(principal, workspace)
          unless record
            record = ActiveRecordRecords::BotInstance.create!(
              service_principal: principal,
              workspace: workspace,
              status: STATUS_ACTIVE
            )
            append_event!(
              record,
              actor: actor,
              action: "created",
              from_status: nil,
              to_status: STATUS_ACTIVE,
              occurred_at: timestamp
            )
          end
          to_domain(record)
        end
      end

      def find(principal_id:, workspace_id:)
        principal_ref = reference(principal_id, "principal_id")
        workspace_ref = reference(workspace_id, "workspace_id")
        record = instance_scope.find_by(
          service_principals: {identifier: principal_ref},
          workspaces: {identifier: workspace_ref}
        )
        record && to_domain(record)
      end

      def pause(principal_id:, workspace_id:, actor_user_identity_id:, occurred_at:)
        transition(
          principal_id: principal_id,
          workspace_id: workspace_id,
          actor_user_identity_id: actor_user_identity_id,
          occurred_at: occurred_at,
          target_status: STATUS_PAUSED,
          action: "paused"
        )
      end

      def resume(principal_id:, workspace_id:, actor_user_identity_id:, occurred_at:)
        transition(
          principal_id: principal_id,
          workspace_id: workspace_id,
          actor_user_identity_id: actor_user_identity_id,
          occurred_at: occurred_at,
          target_status: STATUS_ACTIVE,
          action: "resumed"
        )
      end

      private

      def transition(principal_id:, workspace_id:, actor_user_identity_id:, occurred_at:, target_status:, action:)
        principal_ref = reference(principal_id, "principal_id")
        workspace_ref = reference(workspace_id, "workspace_id")
        actor_ref = reference(actor_user_identity_id, "actor_user_identity_id")
        timestamp = normalized_timestamp(occurred_at)

        ::ActiveRecord::Base.transaction do
          principal, workspace, actor = locked_context!(principal_ref, workspace_ref, actor_ref)
          record = locked_instance(principal, workspace)
          unless record
            record = ActiveRecordRecords::BotInstance.create!(
              service_principal: principal,
              workspace: workspace,
              status: STATUS_ACTIVE
            )
            append_event!(
              record,
              actor: actor,
              action: "created",
              from_status: nil,
              to_status: STATUS_ACTIVE,
              occurred_at: timestamp
            )
          end

          reject_disabled!(record)
          return to_domain(record) if record.status == target_status

          from_status = record.status
          attributes = if target_status == STATUS_PAUSED
            {status: STATUS_PAUSED, paused_at: timestamp, disabled_at: nil}
          else
            {status: STATUS_ACTIVE, paused_at: nil, disabled_at: nil}
          end
          record.update!(attributes)
          append_event!(
            record,
            actor: actor,
            action: action,
            from_status: from_status,
            to_status: target_status,
            occurred_at: timestamp
          )
          to_domain(record)
        end
      end

      def locked_context!(principal_id, workspace_id, actor_user_identity_id)
        principal = ActiveRecordRecords::ServicePrincipal.lock.find_by(identifier: principal_id)
        unless principal&.status == STATUS_ACTIVE
          raise BotInstanceConflictError.new(
            "hub.bot_instance.principal_unavailable",
            "bot lifecycle requires an active service principal"
          )
        end

        workspace = ActiveRecordRecords::Workspace.lock.find_by(identifier: workspace_id)
        unless workspace&.status == STATUS_ACTIVE
          raise BotInstanceConflictError.new(
            "hub.bot_instance.workspace_unavailable",
            "bot lifecycle requires an active workspace"
          )
        end

        actor = ActiveRecordRecords::UserIdentity.lock.find_by(id: actor_user_identity_id)
        membership = actor && ActiveRecordRecords::WorkspaceMembership.lock.find_by(
          workspace: workspace,
          user_identity: actor,
          status: STATUS_ACTIVE,
          role: ROLE_OWNER
        )
        unless actor&.status == STATUS_ACTIVE && membership
          raise BotInstanceConflictError.new(
            "hub.bot_instance.owner_required",
            "bot lifecycle requires the active workspace owner"
          )
        end

        [principal, workspace, actor]
      end

      def locked_instance(principal, workspace)
        ActiveRecordRecords::BotInstance.lock.find_by(
          service_principal: principal,
          workspace: workspace
        )
      end

      def reject_disabled!(record)
        return unless record.status == STATUS_DISABLED

        raise BotInstanceConflictError.new(
          "hub.bot_instance.disabled",
          "disabled bot instances require an administrative recovery operation"
        )
      end

      def append_event!(record, actor:, action:, from_status:, to_status:, occurred_at:)
        record.lifecycle_events.create!(
          actor_user_identity: actor,
          action: action,
          from_status: from_status,
          to_status: to_status,
          occurred_at: occurred_at
        )
      end

      def instance_scope
        ActiveRecordRecords::BotInstance
          .joins(:service_principal, :workspace)
          .includes(:service_principal, :workspace)
      end

      def to_domain(record)
        Domain::BotInstance.new(
          id: record.id,
          principal_id: record.service_principal.identifier,
          workspace_id: record.workspace.identifier,
          status: record.status,
          paused_at: record.paused_at&.to_time&.utc,
          disabled_at: record.disabled_at&.to_time&.utc
        )
      end

      def normalized_timestamp(value)
        return value.utc if value.is_a?(Time)

        raise ArgumentError, "occurred_at must be a Time"
      end

      def reference(value, field)
        string = String(value)
        return string if Domain::Channel::REFERENCE_PATTERN.match?(string)

        raise ArgumentError, "#{field} must be a non-empty stable reference"
      end
    end
  end
end
