# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class RevokeProviderIdentity
      def initialize(binding_repository:, clock:)
        @binding_repository = binding_repository
        @clock = clock
      end

      def call(provider:, provider_scope:, subject_id:)
        @binding_repository.revoke(
          provider_subject: Domain::ProviderSubject.new(
            provider: provider,
            provider_scope: provider_scope,
            subject_id: subject_id
          ),
          revoked_at: @clock.call
        )
      end
    end
  end
end
