# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    class MailboxGateway
      def list(access_token:)
        raise NotImplementedError
      end
    end
  end
end
