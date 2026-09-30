# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordSignalAlertLedger < Ports::SignalAlertLedger
      KIND_ALERT = "alert".freeze

      def recorded?(assessment_id:, workspace_id:, kind:)
        scope.where(assessment_id: assessment_id, delivery_kind: kind, workspace_id: workspace_pk(workspace_id)).exists?
      end

      def recent_alert?(workspace_id:, hazard_class:, since:)
        scope.where(
          workspace_id: workspace_pk(workspace_id),
          hazard_class: hazard_class,
          delivery_kind: KIND_ALERT
        ).where("created_at >= ?", since).exists?
      end

      def record(assessment_id:, workspace_id:, hazard_class:, kind:, event_seq:, at:)
        scope.create!(
          workspace_id: ActiveRecordRecords::Workspace.find_by!(identifier: workspace_id).id,
          assessment_id: assessment_id,
          hazard_class: hazard_class,
          delivery_kind: kind,
          event_seq: event_seq,
          created_at: at,
          updated_at: at
        )
        true
      rescue ::ActiveRecord::RecordNotUnique
        false
      end

      def alerted_workspaces(assessment_id:)
        scope
          .joins(:workspace)
          .where(assessment_id: assessment_id, delivery_kind: KIND_ALERT)
          .pluck("workspaces.identifier")
      end

      def prune(before:)
        scope.where("created_at < ?", before).delete_all
      end

      private

      def scope
        ActiveRecordRecords::SignalAlertDelivery
      end

      # An unknown workspace has no rows, so a lookup by it finds nothing.
      def workspace_pk(identifier)
        ActiveRecordRecords::Workspace.where(identifier: identifier).pick(:id)
      end
    end
  end
end
