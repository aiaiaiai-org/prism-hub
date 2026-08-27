# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ProvisionUserIdentity
      def initialize(user_identity_repository:)
        @user_identity_repository = user_identity_repository
      end

      def call(canonical_type:, canonical_id:)
        identity = Domain::CanonicalIdentityRef.new(type: canonical_type, id: canonical_id)
        unless identity.type == "person"
          raise InputError.new(
            "hub.user_identity.subject.invalid",
            "user identities must reference a canonical person identity"
          )
        end

        @user_identity_repository.provision(canonical_identity: identity)
      end
    end
  end
end
