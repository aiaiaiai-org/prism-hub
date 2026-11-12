# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ProvisionServicePrincipal
      def initialize(repository:)
        @repository = repository
      end

      def call(principal_id:, capabilities:, channel_ids:, product_id: nil)
        @repository.provision(
          principal_id: principal_id,
          capabilities: capabilities,
          channel_ids: channel_ids,
          product_id: product_id
        )
      end
    end
  end
end
