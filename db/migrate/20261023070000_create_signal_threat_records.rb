# © 2026 aiaiaiai · aiaiaiai.org

class CreateSignalThreatRecords < ActiveRecord::Migration[8.1]
  def change
    # Public-source threat episodes, independent of subscribers and delivery logs.
    # Store only a named place, never coordinates or inferred impact points.
    create_table :signal_threat_records, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :assessment_id, null: false, limit: 200
      table.string :hazard_class, null: false, limit: 16
      table.string :hazard_kinds, null: false, array: true, default: []
      table.string :destination_id, limit: 200
      table.string :destination_name, limit: 200
      table.string :status, null: false, limit: 16
      table.datetime :first_reported_at, null: false
      table.datetime :last_reported_at, null: false
      table.datetime :valid_until, null: false
      table.datetime :last_evaluated_at, null: false
      table.jsonb :source_reports, null: false, default: []
      # Reserved for explicitly sourced windows only. No automatic ETA inference.
      table.datetime :reported_arrival_from
      table.datetime :reported_arrival_until
      table.string :arrival_source_url, limit: 2048
      table.timestamps null: false
    end

    add_index :signal_threat_records, :assessment_id,
      unique: true, name: "idx_signal_threat_records_assessment"
    add_index :signal_threat_records, [:status, :valid_until],
      name: "idx_signal_threat_records_status_expiry"
    add_check_constraint :signal_threat_records,
      "hazard_class IN ('drone', 'bomb', 'missile')",
      name: "signal_threat_records_class_check"
    add_check_constraint :signal_threat_records,
      "status IN ('active', 'expired', 'retracted')",
      name: "signal_threat_records_status_check"
    add_check_constraint :signal_threat_records,
      "last_reported_at >= first_reported_at",
      name: "signal_threat_records_report_order_check"
    add_check_constraint :signal_threat_records,
      <<~SQL.squish,
        (reported_arrival_from IS NULL AND reported_arrival_until IS NULL AND arrival_source_url IS NULL)
        OR (reported_arrival_from IS NOT NULL AND reported_arrival_until IS NOT NULL
            AND reported_arrival_from <= reported_arrival_until AND arrival_source_url IS NOT NULL)
      SQL
      name: "signal_threat_records_arrival_provenance_check"
  end
end
