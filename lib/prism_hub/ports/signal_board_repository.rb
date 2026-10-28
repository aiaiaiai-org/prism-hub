# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    # Where each person's board state lives (Domain::SignalBoardState), and where the delivery
    # worker records the message a board or status was delivered in.
    class SignalBoardRepository < DeliveryViewReceipts
      def find(workspace_id:)
        raise NotImplementedError
      end

      # Saves what the planner decided. A message id the planner did not change is left as it is,
      # so a receipt recorded meanwhile is not overwritten.
      def save(state:, previous:)
        raise NotImplementedError
      end
    end
  end
end
