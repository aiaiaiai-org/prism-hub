# © 2026 aiaiaiai · aiaiaiai.org

class CreateBotInstances < ActiveRecord::Migration[8.1]
  def change
    create_table :bot_instances, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :service_principal,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.references :workspace,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.string :status, null: false, limit: 32, default: "active"
      table.datetime :paused_at
      table.datetime :disabled_at
      table.timestamps null: false
    end

    add_index :bot_instances,
      [:service_principal_id, :workspace_id],
      unique: true,
      name: "idx_bot_instances_principal_workspace"
    add_check_constraint :bot_instances,
      "status IN ('active', 'paused', 'disabled')",
      name: "bot_instances_status_check"
    add_check_constraint :bot_instances,
      <<~SQL.squish,
        (status = 'active' AND paused_at IS NULL AND disabled_at IS NULL) OR
        (status = 'paused' AND paused_at IS NOT NULL AND disabled_at IS NULL) OR
        (status = 'disabled' AND paused_at IS NULL AND disabled_at IS NOT NULL)
      SQL
      name: "bot_instances_state_check"

    create_table :bot_instance_lifecycle_events, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :bot_instance,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.references :actor_user_identity,
        null: false,
        type: :uuid,
        foreign_key: {to_table: :user_identities, on_delete: :restrict}
      table.string :action, null: false, limit: 32
      table.string :from_status, limit: 32
      table.string :to_status, null: false, limit: 32
      table.datetime :occurred_at, null: false
    end

    add_index :bot_instance_lifecycle_events,
      [:bot_instance_id, :occurred_at],
      name: "idx_bot_instance_events_instance_time"
    add_check_constraint :bot_instance_lifecycle_events,
      "action IN ('created', 'paused', 'resumed')",
      name: "bot_instance_events_action_check"
    add_check_constraint :bot_instance_lifecycle_events,
      "from_status IS NULL OR from_status IN ('active', 'paused', 'disabled')",
      name: "bot_instance_events_from_status_check"
    add_check_constraint :bot_instance_lifecycle_events,
      "to_status IN ('active', 'paused', 'disabled')",
      name: "bot_instance_events_to_status_check"
  end
end
