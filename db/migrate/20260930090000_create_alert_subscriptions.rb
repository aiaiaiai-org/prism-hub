# © 2026 aiaiaiai · aiaiaiai.org

class CreateAlertSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :alert_subscriptions, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :workspace,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :restrict},
        index: {unique: true, name: "idx_alert_subscriptions_workspace"}
      table.string :cell, null: false, limit: 15
      table.string :categories, null: false, array: true
      table.boolean :include_nearby, null: false, default: true
      table.timestamps null: false
    end

    add_index :alert_subscriptions, :cell, name: "idx_alert_subscriptions_cell"
    add_check_constraint :alert_subscriptions,
      "cell ~ '^86[0-9a-f]{13}$'",
      name: "alert_subscriptions_cell_check"
    add_check_constraint :alert_subscriptions,
      <<~SQL.squish,
        cardinality(categories) BETWEEN 1 AND 3
        AND categories <@ ARRAY['drone', 'bomb', 'missile']::varchar[]
      SQL
      name: "alert_subscriptions_categories_check"
  end
end
