# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class MailOAuthGateway
      def start
        raise NotImplementedError
      end

      def poll(client_id:, device_code:)
        raise NotImplementedError
      end
    end
  end
end
