# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ResolveProviderIdentity
      def initialize(binding_repository:)
        @binding_repository = binding_repository
      end

      def call(provider:, provider_scope:, subject_id:)
        binding = @binding_repository.find(
          provider_subject: Domain::ProviderSubject.new(
            provider: provider,
            provider_scope: provider_scope,
            subject_id: subject_id
          )
        )
        binding if binding&.active? && binding.user_identity.active?
      end
    end
  end
end
