# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class RotateClientCredential
      def initialize(repository:, token_generator:, clock: -> { Time.now.utc })
        @repository = repository
        @token_generator = token_generator
        @clock = clock
      end

      def call(credential_id:, expires_at: nil)
        token = @token_generator.call
        replacement_id = @repository.rotate(
          credential_id: credential_id,
          token: token,
          rotated_at: @clock.call,
          expires_at: expires_at
        )
        Domain::IssuedClientCredential.new(id: replacement_id, token: token, expires_at: expires_at)
      end
    end
  end
end
