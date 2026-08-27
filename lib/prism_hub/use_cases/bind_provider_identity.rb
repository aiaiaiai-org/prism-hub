# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class BindProviderIdentity
      def initialize(user_identity_repository:, binding_repository:)
        @user_identity_repository = user_identity_repository
        @binding_repository = binding_repository
      end

      def call(user_identity_id:, provider:, provider_scope:, subject_id:)
        user_identity = @user_identity_repository.find(id: user_identity_id)
        unless user_identity
          raise UserIdentityNotFoundError.new(
            "hub.user_identity.not_found",
            "user identity was not found"
          )
        end
        unless user_identity.active?
          raise UserIdentityConflictError.new(
            "hub.user_identity.disabled",
            "disabled user identities cannot receive provider bindings"
          )
        end

        @binding_repository.bind(
          user_identity: user_identity,
          provider_subject: Domain::ProviderSubject.new(
            provider: provider,
            provider_scope: provider_scope,
            subject_id: subject_id
          )
        )
      end
    end
  end
end
