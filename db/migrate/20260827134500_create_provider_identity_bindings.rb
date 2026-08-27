# © 2026 aiaiaiai · aiaiaiai.org

class CreateProviderIdentityBindings < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_identity_bindings, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :user_identity,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.string :provider, null: false, limit: 64
      table.string :provider_scope, null: false, limit: 128
      table.string :subject_id, null: false, limit: 512
      table.string :status, null: false, limit: 32, default: "active"
      table.datetime :revoked_at
      table.timestamps null: false
    end

    add_index :provider_identity_bindings,
      [:provider, :provider_scope, :subject_id],
      unique: true,
      name: "idx_provider_identity_bindings_subject"

    add_check_constraint :provider_identity_bindings,
      "provider ~ '^[a-z][a-z0-9._-]{0,63}$'",
      name: "provider_identity_bindings_provider_check"
    add_check_constraint :provider_identity_bindings,
      "provider_scope ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'",
      name: "provider_identity_bindings_scope_check"
    add_check_constraint :provider_identity_bindings,
      "char_length(subject_id) > 0",
      name: "provider_identity_bindings_subject_check"
    add_check_constraint :provider_identity_bindings,
      "status IN ('active', 'revoked')",
      name: "provider_identity_bindings_status_check"
    add_check_constraint :provider_identity_bindings,
      "(status = 'active' AND revoked_at IS NULL) OR (status = 'revoked' AND revoked_at IS NOT NULL)",
      name: "provider_identity_bindings_state_check"
  end
end
