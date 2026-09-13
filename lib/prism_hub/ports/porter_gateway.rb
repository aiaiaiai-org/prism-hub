# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class PorterGateway
      def build_delivery_intent(artifact:, routes:, chunk_max_chars: nil)
        raise NotImplementedError
      end
    end
  end
end
