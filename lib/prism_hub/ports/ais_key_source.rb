# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    # AIS's published signing keys. Answers the public key for a key id, or nil when AIS does not
    # publish one under that id.
    class AisKeySource
      def key(kid:, now:)
        raise NotImplementedError
      end
    end
  end
end
