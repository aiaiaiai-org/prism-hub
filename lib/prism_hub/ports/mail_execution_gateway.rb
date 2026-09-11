# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Ports
    class MailExecutionGateway
      def execute(mailbox_id:, since:, before:, access_token:)
        raise NotImplementedError
      end
    end
  end
end
