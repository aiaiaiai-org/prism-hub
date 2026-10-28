# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    # Where the message id of a delivered board or status is recorded, so the next change edits
    # that message. The default records nothing.
    class DeliveryViewReceipts
      def record(workspace:, slot:, revision:, message_id:)
        nil
      end
    end
  end
end
