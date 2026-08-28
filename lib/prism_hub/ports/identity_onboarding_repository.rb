# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class IdentityOnboardingRepository
      def resolve_or_create(provider_subject:, public_user_id:)
        raise NotImplementedError
      end
    end
  end
end
