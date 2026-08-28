# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ProvisionServicePrincipal
      def initialize(repository:)
        @repository = repository
      end

      def call(principal_id:, capabilities:, channel_ids:)
        @repository.provision(
          principal_id: principal_id,
          capabilities: capabilities,
          channel_ids: channel_ids
        )
      end
    end
  end
end
