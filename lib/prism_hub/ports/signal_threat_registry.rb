# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    # Durable, workspace-independent registry of source-reported threat episodes.
    # It is not a subscriber registry, location tracker or strike prediction engine.
    class SignalThreatRegistry
      def sync(assessments:, now:)
        raise NotImplementedError
      end
    end
  end
end
