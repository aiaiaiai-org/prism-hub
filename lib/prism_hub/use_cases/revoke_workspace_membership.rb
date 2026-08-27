# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class RevokeWorkspaceMembership
      def initialize(workspace_membership_repository:, clock: Time)
        @workspace_membership_repository = workspace_membership_repository
        @clock = clock
      end

      def call(user_identity_id:, workspace_id:)
        @workspace_membership_repository.revoke(
          user_identity_id: user_identity_id,
          workspace_id: workspace_id,
          revoked_at: @clock.now.utc
        )
      end
    end
  end
end
