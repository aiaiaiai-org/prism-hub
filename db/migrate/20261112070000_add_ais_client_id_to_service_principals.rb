# © 2026 aiaiaiai · aiaiaiai.org

class AddAisClientIdToServicePrincipals < ActiveRecord::Migration[8.1]
  def change
    # The AIS client id of a family product (hub.v1). A product token from AIS whose `sub` is
    # this id authenticates as this principal; Hub's own grants still decide what it may do.
    add_column :service_principals, :ais_client_id, :string, limit: 64
    add_index :service_principals, :ais_client_id, unique: true
  end
end
