# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ClientCredentialRepository
      def authenticate(token:, now:)
        raise NotImplementedError
      end

      def issue(workspace_id:, principal_id:, bot_instance_id:, capabilities:, channel_ids:, token:, expires_at:)
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
