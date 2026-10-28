# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class BotDeliveryGateway
      # `view`, when given, asks the bot to edit, delete, or deliver silently; see
      # Domain::DeliveryView.
      def deliver(intent:, binding:, view: nil)
        raise NotImplementedError
      end
    end
  end
end
