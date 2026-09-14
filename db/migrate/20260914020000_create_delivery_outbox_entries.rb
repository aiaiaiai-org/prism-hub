# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

class CreateDeliveryOutboxEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :delivery_outbox_entries, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :workspace, null: false, limit: 100
      table.string :logical_channel, null: false, limit: 100
      table.string :idempotency_key, null: false, limit: 64
      table.jsonb :intent_payload, null: false
      table.string :status, null: false, limit: 16, default: "pending"
      table.integer :attempts, null: false, default: 0
      table.datetime :available_at, null: false
      table.datetime :locked_at
      table.string :lock_token, limit: 64
      table.datetime :delivered_at
      table.datetime :failed_at
      table.string :last_error_code, limit: 160
      table.jsonb :last_error_details
      table.timestamps null: false
    end

    add_index :delivery_outbox_entries, :idempotency_key, unique: true
    add_index :delivery_outbox_entries, [:status, :available_at], name: "idx_delivery_outbox_due"
    add_index :delivery_outbox_entries, :lock_token, unique: true, where: "lock_token IS NOT NULL", name: "idx_delivery_outbox_lock_token"

    add_check_constraint :delivery_outbox_entries,
      "status IN ('pending', 'processing', 'delivered', 'failed')",
      name: "delivery_outbox_entries_status_check"
    add_check_constraint :delivery_outbox_entries,
      "attempts >= 0",
      name: "delivery_outbox_entries_attempts_check"
    add_check_constraint :delivery_outbox_entries,
      "char_length(btrim(workspace)) BETWEEN 1 AND 100",
      name: "delivery_outbox_entries_workspace_check"
    add_check_constraint :delivery_outbox_entries,
      "char_length(btrim(logical_channel)) BETWEEN 1 AND 100",
      name: "delivery_outbox_entries_channel_check"
    add_check_constraint :delivery_outbox_entries,
      "idempotency_key ~ '^[0-9a-f]{64}$'",
      name: "delivery_outbox_entries_idempotency_key_check"
    add_check_constraint :delivery_outbox_entries,
      "(status = 'processing' AND locked_at IS NOT NULL AND lock_token IS NOT NULL) OR status <> 'processing'",
      name: "delivery_outbox_entries_processing_lock_check"
    add_check_constraint :delivery_outbox_entries,
      "(status = 'delivered' AND delivered_at IS NOT NULL) OR status <> 'delivered'",
      name: "delivery_outbox_entries_delivered_at_check"
  end
end
