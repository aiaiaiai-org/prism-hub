# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    # Who was told what. Holds a workspace and an assessment, never a position.
    class SignalAlertLedger
      def recorded?(assessment_id:, workspace_id:, kind:)
        raise NotImplementedError
      end

      def recent_alert?(workspace_id:, hazard_class:, since:)
        raise NotImplementedError
      end

      # Idempotent on (assessment_id, workspace_id, kind).
      def record(assessment_id:, workspace_id:, hazard_class:, kind:, event_seq:, at:)
        raise NotImplementedError
      end

      # Workspaces that were told about the assessment.
      def alerted_workspaces(assessment_id:)
        raise NotImplementedError
      end

      def prune(before:)
        raise NotImplementedError
      end
    end
  end
end
