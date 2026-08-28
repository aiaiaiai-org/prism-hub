# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ClientCredentialRepository
      def authenticate(token:, now:)
        raise NotImplementedError
      end

      def issue(principal_id:, token:, expires_at:)
        raise NotImplementedError
      end

      def rotate(credential_id:, token:, rotated_at:, expires_at:)
        raise NotImplementedError
      end

      def revoke(credential_id:, revoked_at:)
        raise NotImplementedError
      end
    end
  end
end
