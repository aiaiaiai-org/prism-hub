# © 2026 aiaiaiai · aiaiaiai.org

class CreateSignalBoards < ActiveRecord::Migration[8.1]
  def change
    # What one person was last shown of an attack: which Telegram messages hold their board and
    # status, digests of what those said, and how close the danger was. No position: the cell
    # stays in alert_subscriptions, and this row goes with it when the person stops.
    create_table :signal_boards, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :workspace,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :cascade},
        index: {unique: true, name: "idx_signal_boards_workspace"}
      table.bigint :board_message_id
      table.integer :board_revision, null: false, default: 0
      table.integer :board_floor_revision, null: false, default: 0
      table.string :board_digest, limit: 64
      table.datetime :board_sent_at
      table.bigint :status_message_id
      table.integer :status_revision, null: false, default: 0
      table.string :status_digest, limit: 64
      table.datetime :status_sent_at
      table.string :level, null: false, default: "quiet", limit: 8
      table.string :hazards, null: false, array: true, default: []
      table.string :shown_track_ids, null: false, array: true, default: []
      table.integer :ended_count, null: false, default: 0
      table.datetime :episode_started_at
      table.datetime :position_reminded_at
      table.timestamps null: false
    end

    add_check_constraint :signal_boards,
      "level IN ('quiet', 'region', 'here')",
      name: "signal_boards_level_check"
  end
end
