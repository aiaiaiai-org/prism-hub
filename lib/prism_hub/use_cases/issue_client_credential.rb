# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class IssueClientCredential
      def initialize(repository:, token_generator:)
        @repository = repository
        @token_generator = token_generator
      end

      def call(principal_id:, expires_at: nil)
        token = @token_generator.call
        credential_id = @repository.issue(
          principal_id: principal_id,
          token: token,
          expires_at: expires_at
        )
        Domain::IssuedClientCredential.new(id: credential_id, token: token, expires_at: expires_at)
      end
    end
  end
end
