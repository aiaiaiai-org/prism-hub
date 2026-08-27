# © 2026 aiaiaiai · aiaiaiai.org

class CreateWorkspaceMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_memberships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: {on_delete: :restrict}
      t.references :user_identity, null: false, type: :uuid, foreign_key: {on_delete: :restrict}
      t.string :role, null: false, limit: 32
      t.string :status, null: false, default: "active", limit: 32
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :workspace_memberships,
      [:workspace_id, :user_identity_id],
      unique: true,
      name: "idx_workspace_memberships_workspace_user"

    add_check_constraint :workspace_memberships,
      "role IN ('owner', 'admin', 'member')",
      name: "workspace_memberships_role_check"
    add_check_constraint :workspace_memberships,
      "status IN ('active', 'revoked')",
      name: "workspace_memberships_status_check"
    add_check_constraint :workspace_memberships,
      "(status = 'active' AND revoked_at IS NULL) OR (status = 'revoked' AND revoked_at IS NOT NULL)",
      name: "workspace_memberships_state_check"
  end
end
