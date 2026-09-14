# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class BotDeliveryGateway
      def deliver(intent:, binding:)
        raise NotImplementedError
      end
    end
  end
end
