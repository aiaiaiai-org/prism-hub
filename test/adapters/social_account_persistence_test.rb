# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class SocialAccountPersistenceTest < Minitest::Test
  Records = PrismHub::Adapters::ActiveRecordRecords

  def before_setup
    super
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
  end

  def setup
    @person = Records::UserIdentity.create!(canonical_type: "person", canonical_id: "0xsocial-test", status: "active")
    @account = account("provider-id")
    @access = access(@account, @person)
  end

  def after_teardown
    ActiveRecord::Base.connection.rollback_transaction
    super
  end

  def test_one_person_can_access_multiple_accounts_and_one_account_can_have_multiple_people
    other_account = account("other-id")
    other_person = Records::UserIdentity.create!(canonical_type: "person", canonical_id: "0xsocial-other", status: "active")
    access(other_account, @person)
    access(@account, other_person, role: "manager")

    assert_equal [@account.id, other_account.id].sort, @person.social_accounts.pluck(:id).sort
    assert_equal [@person.id, other_person.id].sort, @account.user_identities.pluck(:id).sort
    assert_equal @account, @access.social_account
    assert_equal @person, @access.user_identity
  end

  def test_database_arbitrates_duplicate_identity_and_access
    rejects(ActiveRecord::RecordNotUnique) { account("provider-id") }
    rejects(ActiveRecord::RecordNotUnique) { access(@account, @person) }

    refute_equal @account.id, account("provider-id", provider: "another-provider").id
    refute_equal @account.id, account("Provider-id").id
  end

  def test_metadata_updates_preserve_the_key
    key = @account.attributes.slice("id", "provider", "provider_account_id")
    @account.update!(username: "new_handle", display_name: "New Name")

    assert_equal key, @account.reload.attributes.slice("id", "provider", "provider_account_id")
    assert_equal "new_handle", @account.username
    assert_equal "New Name", @account.display_name
  end

  def test_database_rejects_invalid_account_values
    [
      {provider: nil}, {provider: ""}, {provider: "Instagram"}, {provider: "a" * 65},
      {provider_account_id: nil}, {provider_account_id: ""}, {provider_account_id: "a" * 513},
      {provider_account_id: "id\nsuffix"},
      {username: ""}, {username: "a" * 256},
      {display_name: ""}, {display_name: "a" * 256}
    ].each do |attributes|
      rejects do
        Records::SocialAccount.create!(**{provider: "test", provider_account_id: "new"}.merge(attributes))
      end
    end
  end

  def test_database_accepts_unicode_length_boundaries
    record = Records::SocialAccount.create!(
      provider: "a" * 64, provider_account_id: "і" * 512,
      username: "і" * 255, display_name: "і" * 255
    )

    assert_equal "і" * 512, record.reload.provider_account_id
    assert_equal "і" * 255, record.username
  end

  def test_database_rejects_invalid_access_states_without_model_validation
    ungranted = account("ungranted")
    [
      {role: nil}, {role: "admin"}, {status: nil}, {status: "disabled"},
      {status: "active", revoked_at: Time.utc(2026, 8, 28)},
      {status: "revoked", revoked_at: nil}
    ].each do |attributes|
      rejects do
        Records::SocialAccountAccess.insert_all!([
          {social_account_id: ungranted.id, user_identity_id: @person.id, role: "publisher", status: "active"}.merge(attributes)
        ])
      end
    end
  end

  def test_foreign_keys_and_non_null_references_are_enforced
    new_id = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    [{social_account_id: new_id}, {user_identity_id: new_id},
      {social_account_id: nil}, {user_identity_id: nil}].each do |attributes|
      rejects do
        Records::SocialAccountAccess.insert_all!([
          {social_account_id: @account.id, user_identity_id: @person.id, role: "publisher", status: "active"}.merge(attributes)
        ])
      end
    end
  end

  def test_account_keys_cannot_be_reassigned_by_bulk_writes
    {id: "ffffffff-ffff-4fff-8fff-ffffffffffff", provider: "another-provider", provider_account_id: "different"}.each do |field, value|
      rejects { Records::SocialAccount.where(id: @account.id).update_all(field => value) }
    end
  end

  def test_access_identity_role_and_creation_time_cannot_be_rewritten
    other_account = account("other-id")
    other_person = Records::UserIdentity.create!(canonical_type: "person", canonical_id: "0xsocial-other", status: "active")
    {
      id: "ffffffff-ffff-4fff-8fff-ffffffffffff",
      social_account_id: other_account.id, user_identity_id: other_person.id,
      role: "owner", created_at: Time.utc(2000, 1, 1)
    }.each do |field, value|
      rejects { Records::SocialAccountAccess.where(id: @access.id).update_all(field => value) }
    end
  end

  def test_revocation_is_retained_final_and_idempotent
    time = Time.utc(2026, 8, 28)
    @access.update!(status: "revoked", revoked_at: time)
    @access.update!(status: "revoked", revoked_at: time)

    assert_equal time, @access.reload.revoked_at
    assert_equal [@account.id], @person.social_accounts.pluck(:id)
    rejects { Records::SocialAccountAccess.where(id: @access.id).update_all(status: "active", revoked_at: nil) }
    rejects { Records::SocialAccountAccess.where(id: @access.id).update_all(revoked_at: time + 60) }
    rejects(ActiveRecord::RecordNotUnique) { access(@account, @person) }
  end

  def test_removing_associations_or_deleting_directly_cannot_erase_history
    @access.update!(status: "revoked", revoked_at: Time.utc(2026, 8, 28))

    rejects { @person.social_accounts.clear }
    rejects { @account.user_identities.clear }
    rejects { @person.social_accounts = [] }
    rejects { Records::SocialAccountAccess.where(id: @access.id).delete_all }
    rejects { Records::SocialAccountAccess.find(@access.id).destroy! }
    assert Records::SocialAccountAccess.exists?(@access.id)
  end

  def test_parent_deletion_is_restricted_by_database_and_associations
    rejects(ActiveRecord::InvalidForeignKey) { Records::SocialAccount.where(id: @account.id).delete_all }
    rejects(ActiveRecord::InvalidForeignKey) { Records::UserIdentity.where(id: @person.id).delete_all }

    assert_raises(ActiveRecord::DeleteRestrictionError) { @account.destroy! }
    assert_raises(ActiveRecord::DeleteRestrictionError) { @person.destroy! }
  end

  private

  def account(provider_account_id, provider: "instagram")
    Records::SocialAccount.create!(provider: provider, provider_account_id: provider_account_id)
  end

  def access(account, person, role: "publisher")
    Records::SocialAccountAccess.create!(social_account: account, user_identity: person, role: role)
  end

  def rejects(error = ActiveRecord::StatementInvalid, &block)
    assert_raises(error) do
      ActiveRecord::Base.transaction(requires_new: true, &block)
    end
  end
end
