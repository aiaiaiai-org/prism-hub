# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class BotInstanceLifecycleMigrationTest < Minitest::Test
  def test_database_rejects_incoherent_paused_state
    clear_tables
    principal = PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal.create!(
      identifier: "migration-bot",
      status: "active"
    )
    workspace = PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(
      identifier: "migration-workspace",
      status: "active"
    )

    assert_raises(ActiveRecord::StatementInvalid) do
      PrismHub::Adapters::ActiveRecordRecords::BotInstance.create!(
        service_principal: principal,
        workspace: workspace,
        status: "paused",
        paused_at: nil
      )
    end
  ensure
    clear_tables
  end

  private

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
      bot_instance_lifecycle_events
      bot_instances
      client_credentials
      capability_grants
      channel_grants
      service_principals
      workspace_memberships
      provider_identity_bindings
      user_identities
      workspaces
    ].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
