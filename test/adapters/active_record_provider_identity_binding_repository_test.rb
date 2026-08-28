# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordProviderIdentityBindingRepositoryTest < Minitest::Test
  def setup
    clear_tables
    @identity_repository = PrismHub::Adapters::ActiveRecordUserIdentityRepository.new
    @repository = PrismHub::Adapters::ActiveRecordProviderIdentityBindingRepository.new
    @first_identity = provision_identity("0x0sky")
  end

  def teardown
    clear_tables
  end

  def test_bind_is_idempotent_for_same_identity_and_provider_subject
    first = @repository.bind(user_identity: @first_identity, provider_subject: telegram_subject)
    second = @repository.bind(user_identity: @first_identity, provider_subject: telegram_subject)

    assert_equal first.id, second.id
    assert_equal @first_identity.id, second.user_identity.id
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::ProviderIdentityBinding.count
  end

  def test_active_provider_subject_cannot_be_reassigned_to_another_identity
    @repository.bind(user_identity: @first_identity, provider_subject: telegram_subject)
    second_identity = provision_identity("0xanother-person")

    error = assert_raises(PrismHub::ProviderIdentityBindingConflictError) do
      @repository.bind(user_identity: second_identity, provider_subject: telegram_subject)
    end

    assert_equal "hub.provider_identity_binding.already_bound", error.code
  end

  def test_provider_scope_is_part_of_subject_identity
    first = @repository.bind(user_identity: @first_identity, provider_subject: telegram_subject(scope: "global"))
    second_identity = provision_identity("0xanother-person")
    second = @repository.bind(
      user_identity: second_identity,
      provider_subject: telegram_subject(scope: "bot:secondary")
    )

    refute_equal first.id, second.id
    assert_equal 2, PrismHub::Adapters::ActiveRecordRecords::ProviderIdentityBinding.count
  end

  def test_revoked_provider_subject_cannot_be_rebound_even_to_same_identity
    @repository.bind(user_identity: @first_identity, provider_subject: telegram_subject)
    revoked_at = Time.utc(2026, 8, 27, 13, 45, 0)
    revoked = @repository.revoke(provider_subject: telegram_subject, revoked_at: revoked_at)

    assert_predicate revoked, :revoked?
    assert_equal revoked_at, revoked.revoked_at

    error = assert_raises(PrismHub::ProviderIdentityBindingConflictError) do
      @repository.bind(user_identity: @first_identity, provider_subject: telegram_subject)
    end

    assert_equal "hub.provider_identity_binding.revoked", error.code
  end

  def test_revocation_is_idempotent_and_preserves_first_revocation_time
    @repository.bind(user_identity: @first_identity, provider_subject: telegram_subject)
    first_time = Time.utc(2026, 8, 27, 13, 45, 0)
    second_time = Time.utc(2026, 8, 27, 14, 0, 0)

    @repository.revoke(provider_subject: telegram_subject, revoked_at: first_time)
    second = @repository.revoke(provider_subject: telegram_subject, revoked_at: second_time)

    assert_equal first_time, second.revoked_at
  end

  def test_find_returns_revoked_binding_for_audit_but_not_a_new_owner
    @repository.bind(user_identity: @first_identity, provider_subject: telegram_subject)
    @repository.revoke(
      provider_subject: telegram_subject,
      revoked_at: Time.utc(2026, 8, 27, 13, 45, 0)
    )

    binding = @repository.find(provider_subject: telegram_subject)

    assert_predicate binding, :revoked?
    assert_equal @first_identity.canonical_identity, binding.user_identity.canonical_identity
  end

  private

  def provision_identity(canonical_id)
    @identity_repository.provision(
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: canonical_id)
    )
  end

  def telegram_subject(scope: "global")
    PrismHub::Domain::ProviderSubject.new(
      provider: "telegram",
      provider_scope: scope,
      subject_id: "123456789"
    )
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[provider_identity_bindings user_identities].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
