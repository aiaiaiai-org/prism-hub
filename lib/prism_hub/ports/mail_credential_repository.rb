# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class MailCredentialRepository
      def store(provider:, origin:, resource:, access_token:, refresh_token:, scope:, token_type:, expires_at:)
        raise NotImplementedError
      end

      def fetch(provider:, origin:, resource:)
        raise NotImplementedError
      end
    end
  end
end
