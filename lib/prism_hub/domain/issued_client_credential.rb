# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class IssuedClientCredential
      attr_reader :id, :token, :expires_at

      def initialize(id:, token:, expires_at:)
        @id = String(id).freeze
        @token = String(token).freeze
        @expires_at = expires_at
        freeze
      end

      def inspect
        "#<#{self.class.name} id=#{id.inspect} token=[REDACTED] expires_at=#{expires_at.inspect}>"
      end
    end
  end
end
