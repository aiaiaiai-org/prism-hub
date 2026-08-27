# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ProviderIdentityBindingRepository
      def bind(user_identity:, provider_subject:)
        raise NotImplementedError
      end

      def find(provider_subject:)
        raise NotImplementedError
      end

      def revoke(provider_subject:, revoked_at:)
        raise NotImplementedError
      end
    end
  end
end
