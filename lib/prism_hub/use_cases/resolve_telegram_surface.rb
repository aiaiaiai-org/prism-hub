# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class ResolveTelegramSurface
      def initialize(binding_repository:)
        @binding_repository = binding_repository
      end

      def call(workspace_id:, logical_channel:)
        binding = @binding_repository.find_by_logical_context(
          workspace_id: workspace_id,
          logical_channel: logical_channel
        )
        return binding if binding

        raise TelegramSurfaceBindingNotFoundError.new(
          "hub.telegram_surface_binding.not_found",
          "no active Telegram surface is bound to the logical context"
        )
      end
    end
  end
end
