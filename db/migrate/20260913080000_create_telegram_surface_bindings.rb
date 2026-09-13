# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

class CreateTelegramSurfaceBindings < ActiveRecord::Migration[8.1]
  def change
    create_table :telegram_surface_bindings, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :workspace,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.references :bot_instance,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict}
      table.string :logical_channel, null: false, limit: 100
      table.bigint :chat_id, null: false
      table.bigint :message_thread_id
      table.references :created_by_user_identity,
        null: false,
        type: :uuid,
        foreign_key: {to_table: :user_identities, on_delete: :restrict}
      table.string :status, null: false, limit: 16, default: "active"
      table.datetime :revoked_at
      table.references :revoked_by_user_identity,
        type: :uuid,
        foreign_key: {to_table: :user_identities, on_delete: :restrict}
      table.timestamps null: false
    end

    add_index :telegram_surface_bindings,
      [:workspace_id, :logical_channel],
      unique: true,
      where: "status = 'active'",
      name: "idx_tg_surface_bindings_active_logical"
    add_index :telegram_surface_bindings,
      [:bot_instance_id, :chat_id],
      unique: true,
      where: "status = 'active' AND message_thread_id IS NULL",
      name: "idx_tg_surface_bindings_active_root"
    add_index :telegram_surface_bindings,
      [:bot_instance_id, :chat_id, :message_thread_id],
      unique: true,
      where: "status = 'active' AND message_thread_id IS NOT NULL",
      name: "idx_tg_surface_bindings_active_topic"

    add_check_constraint :telegram_surface_bindings,
      "status IN ('active', 'revoked')",
      name: "telegram_surface_bindings_status_check"
    add_check_constraint :telegram_surface_bindings,
      "char_length(btrim(logical_channel)) BETWEEN 1 AND 100",
      name: "telegram_surface_bindings_logical_channel_check"
    add_check_constraint :telegram_surface_bindings,
      "chat_id <> 0",
      name: "telegram_surface_bindings_chat_id_check"
    add_check_constraint :telegram_surface_bindings,
      "message_thread_id IS NULL OR message_thread_id > 0",
      name: "telegram_surface_bindings_thread_id_check"
    add_check_constraint :telegram_surface_bindings,
      <<~SQL.squish,
        (status = 'active' AND revoked_at IS NULL AND revoked_by_user_identity_id IS NULL) OR
        (status = 'revoked' AND revoked_at IS NOT NULL AND revoked_by_user_identity_id IS NOT NULL)
      SQL
      name: "telegram_surface_bindings_state_check"
  end
end
