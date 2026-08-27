# © 2026 aiaiaiai · aiaiaiai.org

class CreateUserIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_identities, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :canonical_type, null: false, limit: 32
      table.string :canonical_id, null: false, limit: 255
      table.string :status, null: false, limit: 32, default: "active"
      table.timestamps null: false
    end
    add_index :user_identities, [:canonical_type, :canonical_id], unique: true
    add_check_constraint :user_identities,
      "canonical_type = 'person'",
      name: "user_identities_canonical_type_check"
    add_check_constraint :user_identities,
      "char_length(canonical_id) BETWEEN 1 AND 255",
      name: "user_identities_canonical_id_check"
    add_check_constraint :user_identities,
      "status IN ('active', 'disabled')",
      name: "user_identities_status_check"
  end
end
