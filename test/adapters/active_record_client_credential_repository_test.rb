# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordClientCredentialRepositoryTest < Minitest::Test
  TOKEN = "prism_client_v1_#{'b' * 43}".freeze
  ROTATED_TOKEN = "prism_client_v1_#{'c' * 43}".freeze
  NOW = Time.utc(2026, 8, 27, 9, 47, 0)

  def setup
    clear_identity_tables
    @principals = PrismHub::Adapters::ActiveRecordServicePrincipalRepository.new
    @repository = PrismHub::Adapters::ActiveRecordClientCredentialRepository.new
    provision_principal
  end

  def teardown
    clear_identity_tables
  end

  def test_issue_persists_only_a_digest_and_authenticates_scoped_context
    credential_id = issue(TOKEN, expires_at: NOW + 3600)

    credential = PrismHub::Adapters::ActiveRecordRecords::ClientCredential.find(credential_id)
    refute_equal TOKEN, credential.token_digest
    assert_equal Digest::SHA256.hexdigest(TOKEN), credential.token_digest

    context = @repository.authenticate(token: TOKEN, now: NOW)
    assert_equal "personal", context.workspace_id
    assert_equal "telegram-personal", context.principal_id
    assert_equal ["channels:read", "publications:publish"], context.capabilities
    assert_equal ["personal-threads"], context.allowed_channel_ids
  end

  def test_issuing_another_credential_never_changes_principal_grants
    issue(TOKEN)
    issue(ROTATED_TOKEN)

    context = @repository.authenticate(token: ROTATED_TOKEN, now: NOW)
    assert_equal ["channels:read", "publications:publish"], context.capabilities
    assert_equal ["personal-threads"], context.allowed_channel_ids
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::CapabilityGrant.where(capability: "channels:read").count
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::ChannelGrant.where(channel_id: "personal-threads").count
  end

  def test_expired_or_revoked_credentials_do_not_authenticate
    credential_id = issue(TOKEN, expires_at: NOW - 1)

    assert_nil @repository.authenticate(token: TOKEN, now: NOW)

    PrismHub::Adapters::ActiveRecordRecords::ClientCredential.find(credential_id).update!(expires_at: NOW + 3600)
    @repository.revoke(credential_id: credential_id, revoked_at: NOW)
    assert_nil @repository.authenticate(token: TOKEN, now: NOW)
  end

  def test_rotation_revokes_old_secret_and_activates_replacement_atomically
    credential_id = issue(TOKEN)

    replacement_id = @repository.rotate(
      credential_id: credential_id,
      token: ROTATED_TOKEN,
      rotated_at: NOW,
      expires_at: nil
    )

    assert_nil @repository.authenticate(token: TOKEN, now: NOW)
    refute_nil @repository.authenticate(token: ROTATED_TOKEN, now: NOW)
    assert_equal NOW.to_i,
      PrismHub::Adapters::ActiveRecordRecords::ClientCredential.find(credential_id).revoked_at.to_i
    refute_equal credential_id, replacement_id
  end

  def test_issue_requires_an_explicitly_provisioned_service_principal
    error = assert_raises(PrismHub::ServicePrincipalNotFoundError) do
      @repository.issue(
        workspace_id: "other",
        principal_id: "missing",
        token: ROTATED_TOKEN,
        expires_at: nil
      )
    end

    assert_equal "hub.service_principal.not_found", error.code
  end

  private

  def provision_principal
    @principals.provision(
      workspace_id: "personal",
      principal_id: "telegram-personal",
      bot_instance_id: "prisma-telegram",
      capabilities: ["publications:publish", "channels:read"],
      channel_ids: ["personal-threads"]
    )
  end

  def issue(token, expires_at: nil)
    @repository.issue(
      workspace_id: "personal",
      principal_id: "telegram-personal",
      token: token,
      expires_at: expires_at
    )
  end

  def clear_identity_tables
    connection = ActiveRecord::Base.connection
    %w[channel_grants capability_grants client_credentials service_principals workspaces].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
