# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ListMailboxes
      def initialize(credential_resolver:, mailbox_gateway:)
        @credential_resolver = credential_resolver
        @mailbox_gateway = mailbox_gateway
      end

      def call
        credential = @credential_resolver.call
        @mailbox_gateway.list(access_token: credential.access_token)
      end
    end
  end
end
