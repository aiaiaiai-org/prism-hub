# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    module ActiveRecordRecords
      class MailProviderCredential < ::ActiveRecord::Base
        self.table_name = "mail_provider_credentials"
      end
    end
  end
end
