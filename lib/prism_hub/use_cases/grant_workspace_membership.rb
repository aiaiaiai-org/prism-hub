# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class GrantWorkspaceMembership
      def initialize(user_identity_repository:, workspace_membership_repository:)
        @user_identity_repository = user_identity_repository
        @workspace_membership_repository = workspace_membership_repository
      end

      def call(user_identity_id:, workspace_id:, role:)
        identity = @user_identity_repository.find(id: user_identity_id)
        unless identity
          raise UserIdentityNotFoundError.new(
            "hub.user_identity.not_found",
            "user identity was not found"
          )
        end

        @workspace_membership_repository.grant(
          user_identity: identity,
          workspace_id: workspace_id,
          role: role
        )
      end
    end
  end
end
