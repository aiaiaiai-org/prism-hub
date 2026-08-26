# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class ExecutionGateway
      def execute(_envelope)
        raise NotImplementedError
      end
    end
  end
end
