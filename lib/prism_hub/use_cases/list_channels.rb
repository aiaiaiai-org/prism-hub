# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ListChannels
      def initialize(channel_repository:)
        @channel_repository = channel_repository
      end

      def call(authorisation_context:, limit:, after_id: nil)
        require_capability!(authorisation_context)
        page = @channel_repository.page(
          limit: limit,
          after_id: after_id,
          allowed_ids: authorisation_context.allowed_channel_ids
        )
        {
          "channels" => page.channels.map(&:public_attributes),
          "next_after_id" => page.next_after_id
        }
      end

      private

      def require_capability!(authorisation_context)
        return if authorisation_context.allows_capability?(Domain::Capabilities::CHANNELS_READ)

        raise AuthorisationError.new(
          "hub.authorization.capability_denied",
          "the authenticated principal cannot read channels"
        )
      end
    end
  end
end
