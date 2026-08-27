# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class WorkspaceMembershipRepository
      def grant(user_identity:, workspace_id:, role:)
        raise NotImplementedError
      end

      def find(user_identity_id:, workspace_id:)
        raise NotImplementedError
      end

      def revoke(user_identity_id:, workspace_id:, revoked_at:)
        raise NotImplementedError
      end
    end
  end
end
