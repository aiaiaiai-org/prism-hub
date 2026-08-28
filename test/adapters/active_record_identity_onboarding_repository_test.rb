# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordIdentityOnboardingRepositoryTest < Minitest::Test
  WorkspaceIds = Struct.new(:value) do
    def call(_public_user_id)
      value
    end
  end

  def setup
    clear_tables
    @repository = PrismHub::Adapters::ActiveRecordIdentityOnboardingRepository.new(
      workspace_id_factory: WorkspaceIds.new("personal-test")
    )
  end

  def teardown
    clear_tables
  end

  def test_atomically_creates_the_identity_binding_personal_workspace_and_owner
    membership = @repository.resolve_or_create(
      provider_subject: telegram_subject,
      public_user_id: "0xnew-user"
    )

    assert_equal "0xnew-user", membership.user_identity.canonical_identity.id
    assert_equal "personal-test", membership.workspace_id
    assert_equal "owner", membership.role
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::UserIdentity.count
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::ProviderIdentityBinding.count
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::Workspace.count
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::WorkspaceMembership.count
  end

  def test_existing_subject_returns_the_same_complete_onboarding
    first = @repository.resolve_or_create(
      provider_subject: telegram_subject,
      public_user_id: "0xfirst-user"
    )
    second = @repository.resolve_or_create(
      provider_subject: telegram_subject,
      public_user_id: "0xignored-candidate"
    )

    assert_equal first.user_identity.id, second.user_identity.id
    assert_equal first.workspace_id, second.workspace_id
    assert_equal "0xfirst-user", second.user_identity.canonical_identity.id
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::UserIdentity.count
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::Workspace.count
  end

  def test_revoked_subject_is_denied_without_creating_new_state
    @repository.resolve_or_create(
      provider_subject: telegram_subject,
      public_user_id: "0xfirst-user"
    )
    PrismHub::Adapters::ActiveRecordRecords::ProviderIdentityBinding.update_all(
      status: "revoked",
      revoked_at: Time.utc(2026, 8, 28)
    )

    error = assert_raises(PrismHub::IdentityOnboardingDeniedError) do
      @repository.resolve_or_create(
        provider_subject: telegram_subject,
        public_user_id: "0xsecond-user"
      )
    end

    assert_equal "hub.identity_onboarding.denied", error.code
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::UserIdentity.count
  end

  def test_public_user_id_collision_requests_a_new_candidate
    @repository.resolve_or_create(
      provider_subject: telegram_subject,
      public_user_id: "0xshared-user"
    )

    error = assert_raises(PrismHub::PublicUserIdConflictError) do
      @repository.resolve_or_create(
        provider_subject: telegram_subject(subject_id: "987654321"),
        public_user_id: "0xshared-user"
      )
    end

    assert_equal "hub.user_identity.public_id.conflict", error.code
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::UserIdentity.count
  end

  private

  def telegram_subject(subject_id: "123456789")
    PrismHub::Domain::ProviderSubject.new(
      provider: "telegram",
      provider_scope: "global",
      subject_id: subject_id
    )
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
      workspace_memberships
      provider_identity_bindings
      client_credentials
      capability_grants
      channel_grants
      service_principals
      user_identities
      workspaces
    ].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
