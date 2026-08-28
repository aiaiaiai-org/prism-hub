# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordServicePrincipalRepositoryTest < Minitest::Test
  def setup
    clear_identity_tables
    @repository = PrismHub::Adapters::ActiveRecordServicePrincipalRepository.new
  end

  def teardown
    clear_identity_tables
  end

  def test_provision_is_idempotent_when_identity_and_grants_match
    provision
    provision

    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::Workspace.count
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal.count
    assert_equal 2, PrismHub::Adapters::ActiveRecordRecords::CapabilityGrant.count
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::ChannelGrant.count
  end

  def test_provision_never_mutates_grants_implicitly
    provision

    error = assert_raises(PrismHub::ServicePrincipalConflictError) do
      provision(capabilities: ["channels:read"], channel_ids: ["personal-instagram"])
    end

    assert_equal "hub.service_principal.grants_mismatch", error.code
    principal = PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal.first
    assert_equal ["channels:read", "publications:publish"], principal.capability_grants.pluck(:capability).sort
    assert_equal ["personal-threads"], principal.channel_grants.pluck(:channel_id).sort
  end

  def test_new_principal_has_no_legacy_workspace_or_bot_binding
    provision

    principal = PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal.first
    assert_nil principal.legacy_workspace_id
    assert_nil principal.legacy_bot_instance_id
  end

  def test_unknown_capability_is_rejected_before_persistence
    error = assert_raises(ArgumentError) do
      provision(capabilities: ["publications:publsih"])
    end

    assert_equal "capability is not supported by this Hub API version", error.message
    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal.count
  end

  private

  def provision(
    capabilities: ["channels:read", "publications:publish"],
    channel_ids: ["personal-threads"]
  )
    @repository.provision(
      principal_id: "telegram-personal",
      capabilities: capabilities,
      channel_ids: channel_ids
    )
  end

  def clear_identity_tables
    connection = ActiveRecord::Base.connection
    %w[channel_grants capability_grants client_credentials service_principals workspaces].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
