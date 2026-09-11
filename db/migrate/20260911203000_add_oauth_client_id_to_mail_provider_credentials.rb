# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

class AddOauthClientIdToMailProviderCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_provider_credentials, :oauth_client_id, :string, limit: 255
    add_check_constraint :mail_provider_credentials,
      "oauth_client_id IS NULL OR char_length(oauth_client_id) > 0",
      name: "mail_provider_credentials_oauth_client_id_check"
  end
end
