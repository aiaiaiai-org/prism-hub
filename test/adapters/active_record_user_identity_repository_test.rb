# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordUserIdentityRepositoryTest < Minitest::Test
  def setup
    clear_tables
    @repository = PrismHub::Adapters::ActiveRecordUserIdentityRepository.new
  end

  def teardown
    clear_tables
  end

  def test_provision_is_idempotent_for_the_same_canonical_person
    identity = canonical_person

    first = @repository.provision(canonical_identity: identity)
    second = @repository.provision(canonical_identity: identity)

    assert_equal first.id, second.id
    assert_equal identity, second.canonical_identity
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::UserIdentity.count
  end

  def test_same_canonical_id_in_different_identity_type_is_not_silently_collapsed
    organization = PrismHub::Domain::CanonicalIdentityRef.new(type: "organization", id: "0x0sky")

    error = assert_raises(ArgumentError) do
      @repository.provision(canonical_identity: organization)
    end

    assert_equal "user identities require a canonical person identity", error.message
    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::UserIdentity.count
  end

  def test_disabled_identity_cannot_be_reprovisioned
    identity = @repository.provision(canonical_identity: canonical_person)
    PrismHub::Adapters::ActiveRecordRecords::UserIdentity.find(identity.id).update!(status: "disabled")

    error = assert_raises(PrismHub::UserIdentityConflictError) do
      @repository.provision(canonical_identity: canonical_person)
    end

    assert_equal "hub.user_identity.disabled", error.code
  end

  private

  def canonical_person
    PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky")
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[workspace_memberships provider_identity_bindings user_identities].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
