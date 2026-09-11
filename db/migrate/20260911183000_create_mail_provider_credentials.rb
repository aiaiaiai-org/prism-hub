# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

class CreateMailProviderCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :mail_provider_credentials, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :provider, null: false, limit: 64
      table.string :origin, null: false, limit: 2048
      table.string :resource, null: false, limit: 2048
      table.text :access_token_ciphertext, null: false
      table.text :refresh_token_ciphertext
      table.text :scope, null: false
      table.string :token_type, null: false, limit: 32
      table.datetime :expires_at
      table.string :status, null: false, limit: 32, default: "active"
      table.datetime :revoked_at
      table.timestamps null: false
    end

    add_index :mail_provider_credentials,
      [:provider, :origin, :resource],
      unique: true,
      name: "idx_mail_provider_credentials_identity"
    add_check_constraint :mail_provider_credentials,
      "provider ~ '^[a-z][a-z0-9._-]{0,63}$'",
      name: "mail_provider_credentials_provider_check"
    add_check_constraint :mail_provider_credentials,
      "origin ~ '^https://[^/]+$'",
      name: "mail_provider_credentials_origin_check"
    add_check_constraint :mail_provider_credentials,
      "resource ~ '^https://[^/]+/api/v[0-9]+$'",
      name: "mail_provider_credentials_resource_check"
    add_check_constraint :mail_provider_credentials,
      "char_length(access_token_ciphertext) > 0",
      name: "mail_provider_credentials_access_token_check"
    add_check_constraint :mail_provider_credentials,
      "refresh_token_ciphertext IS NULL OR char_length(refresh_token_ciphertext) > 0",
      name: "mail_provider_credentials_refresh_token_check"
    add_check_constraint :mail_provider_credentials,
      "char_length(scope) > 0",
      name: "mail_provider_credentials_scope_check"
    add_check_constraint :mail_provider_credentials,
      "char_length(token_type) > 0",
      name: "mail_provider_credentials_token_type_check"
    add_check_constraint :mail_provider_credentials,
      "status IN ('active', 'revoked')",
      name: "mail_provider_credentials_status_check"
    add_check_constraint :mail_provider_credentials,
      "(status = 'active' AND revoked_at IS NULL) OR (status = 'revoked' AND revoked_at IS NOT NULL)",
      name: "mail_provider_credentials_state_check"
  end
end
