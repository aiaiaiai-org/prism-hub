# © 2026 aiaiaiai · aiaiaiai.org

class DecoupleServicePrincipalsFromWorkspaces < ActiveRecord::Migration[8.1]
  def up
    ensure_globally_unique_identifiers!

    remove_index :service_principals,
      name: "index_service_principals_on_workspace_id_and_identifier"
    remove_index :service_principals,
      name: "index_service_principals_on_workspace_id_and_bot_instance_id"

    rename_column :service_principals, :workspace_id, :legacy_workspace_id
    rename_column :service_principals, :bot_instance_id, :legacy_bot_instance_id
    change_column_null :service_principals, :legacy_workspace_id, true
    change_column_null :service_principals, :legacy_bot_instance_id, true

    add_index :service_principals, :identifier, unique: true
  end

  def down
    ensure_legacy_bindings_complete!

    remove_index :service_principals, :identifier
    change_column_null :service_principals, :legacy_workspace_id, false
    change_column_null :service_principals, :legacy_bot_instance_id, false
    rename_column :service_principals, :legacy_workspace_id, :workspace_id
    rename_column :service_principals, :legacy_bot_instance_id, :bot_instance_id

    add_index :service_principals, [:workspace_id, :identifier], unique: true
    add_index :service_principals, [:workspace_id, :bot_instance_id], unique: true
  end

  private

  def ensure_globally_unique_identifiers!
    duplicate = connection.select_value(<<~SQL.squish)
      SELECT identifier
      FROM service_principals
      GROUP BY identifier
      HAVING COUNT(*) > 1
      LIMIT 1
    SQL
    return unless duplicate

    raise ActiveRecord::MigrationError,
      "service principal identifiers must be globally unique before tenancy decoupling"
  end

  def ensure_legacy_bindings_complete!
    incomplete = connection.select_value(<<~SQL.squish)
      SELECT id
      FROM service_principals
      WHERE legacy_workspace_id IS NULL OR legacy_bot_instance_id IS NULL
      LIMIT 1
    SQL
    return unless incomplete

    raise ActiveRecord::MigrationError,
      "global service principals cannot be rolled back to workspace-bound principals"
  end
end
