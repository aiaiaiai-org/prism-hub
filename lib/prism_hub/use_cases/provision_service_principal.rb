# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ProvisionServicePrincipal
      def initialize(repository:)
        @repository = repository
      end

      def call(workspace_id:, principal_id:, bot_instance_id:, capabilities:, channel_ids:)
        @repository.provision(
          workspace_id: workspace_id,
          principal_id: principal_id,
          bot_instance_id: bot_instance_id,
          capabilities: capabilities,
          channel_ids: channel_ids
        )
      end
    end
  end
end
