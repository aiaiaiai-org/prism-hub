# © 2026 aiaiaiai · aiaiaiai.org

class CreateSignalWindow < ActiveRecord::Migration[8.1]
  def change
    # What the sources said, kept only as long as the scheduler's window needs it. The runtime is
    # stateless, so this window is what every assessment is recomputed from.
    create_table :signal_evidence, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :source_id, null: false, limit: 200
      table.string :external_id, null: false, limit: 200
      table.datetime :published_at, null: false
      table.jsonb :payload, null: false
      table.timestamps null: false
    end
    add_index :signal_evidence, [:source_id, :external_id],
      unique: true,
      name: "idx_signal_evidence_source_external"
    add_index :signal_evidence, :published_at, name: "idx_signal_evidence_published_at"

    # Where each source was last read to, so the next poll asks only for what is newer.
    create_table :signal_source_cursors, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :source_id, null: false, limit: 200
      table.string :cursor, null: false, limit: 200
      table.timestamps null: false
    end
    add_index :signal_source_cursors, :source_id,
      unique: true,
      name: "idx_signal_source_cursors_source"

    # Who was told what. It answers three questions and nothing else: was this person already told
    # about this assessment, were they told recently about this kind of hazard, and whom does a
    # retraction reach. A person is only ever told a retraction of something they were told.
    create_table :signal_alert_deliveries, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :workspace,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict},
        index: false
      table.string :assessment_id, null: false, limit: 200
      table.string :hazard_class, null: false, limit: 16
      table.string :delivery_kind, null: false, limit: 16
      table.integer :event_seq, null: false
      table.timestamps null: false
    end
    add_index :signal_alert_deliveries, [:assessment_id, :workspace_id, :delivery_kind],
      unique: true,
      name: "idx_signal_alert_deliveries_once"
    add_index :signal_alert_deliveries, [:workspace_id, :hazard_class, :created_at],
      name: "idx_signal_alert_deliveries_cooldown"
    add_index :signal_alert_deliveries, :created_at,
      name: "idx_signal_alert_deliveries_created_at"
    add_check_constraint :signal_alert_deliveries,
      "delivery_kind IN ('alert', 'retraction')",
      name: "signal_alert_deliveries_kind_check"
    add_check_constraint :signal_alert_deliveries,
      "hazard_class IN ('drone', 'bomb', 'missile')",
      name: "signal_alert_deliveries_class_check"
  end
end
