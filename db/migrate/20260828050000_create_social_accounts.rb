# © 2026 aiaiaiai · aiaiaiai.org

class CreateSocialAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :social_accounts, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :provider, null: false, limit: 64
      table.string :provider_account_id, null: false, limit: 512
      table.string :username, limit: 255
      table.string :display_name, limit: 255
      table.timestamps null: false
    end

    add_index :social_accounts,
      [:provider, :provider_account_id],
      unique: true,
      name: "idx_social_accounts_provider_account"
    add_check_constraint :social_accounts,
      "provider ~ '^[a-z][a-z0-9._-]{0,63}$'",
      name: "social_accounts_provider_check"
    add_check_constraint :social_accounts,
      "char_length(provider_account_id) > 0",
      name: "social_accounts_provider_account_id_check"
    add_check_constraint :social_accounts,
      "username IS NULL OR char_length(username) > 0",
      name: "social_accounts_username_check"
    add_check_constraint :social_accounts,
      "display_name IS NULL OR char_length(display_name) > 0",
      name: "social_accounts_display_name_check"

    create_table :social_account_accesses, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :social_account,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.references :user_identity,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.string :role, null: false, limit: 32
      table.string :status, null: false, limit: 32, default: "active"
      table.datetime :revoked_at
      table.timestamps null: false
    end

    add_index :social_account_accesses,
      [:social_account_id, :user_identity_id],
      unique: true,
      name: "idx_social_account_accesses_account_user"
    add_check_constraint :social_account_accesses,
      "role IN ('owner', 'manager', 'publisher')",
      name: "social_account_accesses_role_check"
    add_check_constraint :social_account_accesses,
      "status IN ('active', 'revoked')",
      name: "social_account_accesses_status_check"
    add_check_constraint :social_account_accesses,
      "(status = 'active' AND revoked_at IS NULL) OR (status = 'revoked' AND revoked_at IS NOT NULL)",
      name: "social_account_accesses_state_check"
  end
end
