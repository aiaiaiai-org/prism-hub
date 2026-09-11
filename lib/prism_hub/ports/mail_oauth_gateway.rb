# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class MailOauthGateway
      def start
        raise NotImplementedError
      end

      def poll(client_id:, device_code:)
        raise NotImplementedError
      end

      def refresh(client_id:, refresh_token:)
        raise NotImplementedError
      end
    end
  end
end
