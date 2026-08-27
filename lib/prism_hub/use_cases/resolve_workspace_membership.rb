# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ResolveWorkspaceMembership
      def initialize(workspace_membership_repository:)
        @workspace_membership_repository = workspace_membership_repository
      end

      def call(user_identity_id:, workspace_id:)
        membership = @workspace_membership_repository.find(
          user_identity_id: user_identity_id,
          workspace_id: workspace_id
        )
        return nil unless membership
        return nil unless membership.active? && membership.user_identity.active?

        membership
      end
    end
  end
end
