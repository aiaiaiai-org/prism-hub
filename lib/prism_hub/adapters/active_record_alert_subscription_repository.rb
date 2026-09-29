# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordAlertSubscriptionRepository < Ports::AlertSubscriptionRepository
      STATUS_ACTIVE = "active".freeze
      ROLE_OWNER = "owner".freeze

      def find(workspace_id:)
        workspace_ref = reference(workspace_id, "workspace_id")
        record = ActiveRecordRecords::AlertSubscription
          .joins(:workspace)
          .includes(:workspace)
          .find_by(workspaces: {identifier: workspace_ref})
        record && to_domain(record)
      end

      def save(workspace_id:, actor_user_identity_id:, cell:, categories:, include_nearby:, occurred_at:)
        workspace_ref = reference(workspace_id, "workspace_id")
        actor_ref = reference(actor_user_identity_id, "actor_user_identity_id")
        timestamp = normalized_timestamp(occurred_at)

        ::ActiveRecord::Base.transaction do
          workspace = locked_owned_workspace!(workspace_ref, actor_ref)
          record = ActiveRecordRecords::AlertSubscription.find_by(workspace: workspace)
          attributes = {cell: cell, categories: categories, include_nearby: include_nearby, updated_at: timestamp}
          if record
            record.update!(attributes)
          else
            record = ActiveRecordRecords::AlertSubscription.create!(
              attributes.merge(workspace: workspace, created_at: timestamp)
            )
          end
          to_domain(record)
        end
      end

      def clear(workspace_id:, actor_user_identity_id:, occurred_at:)
        workspace_ref = reference(workspace_id, "workspace_id")
        actor_ref = reference(actor_user_identity_id, "actor_user_identity_id")
        normalized_timestamp(occurred_at)

        ::ActiveRecord::Base.transaction do
          workspace = locked_owned_workspace!(workspace_ref, actor_ref)
          ActiveRecordRecords::AlertSubscription.where(workspace: workspace).delete_all
        end
        nil
      end

      private

      # The workspace row is locked, which serialises every change to one person's subscription.
      # The actor must be its active owner: a subscription says where someone is, so nobody else
      # may set or clear it.
      def locked_owned_workspace!(workspace_id, actor_user_identity_id)
        workspace = ActiveRecordRecords::Workspace.lock.find_by(identifier: workspace_id)
        unless workspace&.status == STATUS_ACTIVE
          raise AlertSubscriptionConflictError.new(
            "hub.alert_subscription.workspace_unavailable",
            "alert subscriptions require an active workspace"
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
          raise AlertSubscriptionConflictError.new(
            "hub.alert_subscription.owner_required",
            "alert subscriptions require the active workspace owner"
          )
        end

        workspace
      end

      def to_domain(record)
        Domain::AlertSubscription.new(
          workspace_id: record.workspace.identifier,
          cell: record.cell,
          categories: record.categories,
          include_nearby: record.include_nearby,
          updated_at: record.updated_at.to_time.utc
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
