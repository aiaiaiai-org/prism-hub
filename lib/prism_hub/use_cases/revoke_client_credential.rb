# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class RevokeClientCredential
      def initialize(repository:, clock: -> { Time.now.utc })
        @repository = repository
        @clock = clock
      end

      def call(credential_id:)
        @repository.revoke(credential_id: credential_id, revoked_at: @clock.call)
      end
    end
  end
end
