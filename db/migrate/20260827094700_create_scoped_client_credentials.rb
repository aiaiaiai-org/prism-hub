# © 2026 aiaiaiai · aiaiaiai.org

class CreateScopedClientCredentials < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :workspaces, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :identifier, null: false, limit: 128
      table.string :status, null: false, limit: 32, default: "active"
      table.timestamps null: false
    end
    add_index :workspaces, :identifier, unique: true
    add_check_constraint :workspaces,
      "status IN ('active', 'disabled')",
      name: "workspaces_status_check"

    create_table :service_principals, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :workspace,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.string :identifier, null: false, limit: 128
      table.string :bot_instance_id, null: false, limit: 128
      table.string :status, null: false, limit: 32, default: "active"
      table.timestamps null: false
    end
    add_index :service_principals, [:workspace_id, :identifier], unique: true
    add_index :service_principals, [:workspace_id, :bot_instance_id], unique: true
    add_check_constraint :service_principals,
      "status IN ('active', 'disabled')",
      name: "service_principals_status_check"

    create_table :client_credentials, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :service_principal,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :cascade}
      table.string :token_digest, null: false, limit: 64
      table.datetime :expires_at
      table.datetime :revoked_at
      table.timestamps null: false
    end
    add_index :client_credentials, :token_digest, unique: true
    add_check_constraint :client_credentials,
      "token_digest ~ '^[0-9a-f]{64}$'",
      name: "client_credentials_digest_check"

    create_table :capability_grants, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :service_principal,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :cascade}
      table.string :capability, null: false, limit: 128
      table.timestamps null: false
    end
    add_index :capability_grants, [:service_principal_id, :capability], unique: true

    create_table :channel_grants, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :service_principal,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :cascade}
      table.string :channel_id, null: false, limit: 128
      table.timestamps null: false
    end
    add_index :channel_grants, [:service_principal_id, :channel_id], unique: true
  end
end
