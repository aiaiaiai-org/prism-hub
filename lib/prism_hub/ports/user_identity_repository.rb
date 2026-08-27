# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class UserIdentityRepository
      def provision(canonical_identity:)
        raise NotImplementedError
      end

      def find(id:)
        raise NotImplementedError
      end
    end
  end
end
