# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class SocialAccountTest < Minitest::Test
  def test_preserves_opaque_identity_and_optional_metadata
    account = build(provider_account_id: " Case:/іD ", username: "old_handle", display_name: "Display Name")

    assert_equal "instagram", account.provider
    assert_equal " Case:/іD ", account.provider_account_id
    assert_equal "old_handle", account.username
    assert_equal "Display Name", account.display_name
    assert_nil build.username
    assert_nil build.display_name
  end

  def test_rejects_invalid_references_with_stable_errors
    {
      id: [nil, ""],
      provider: [nil, "", "Instagram", "1provider", "a" * 65, "bad\nprovider"],
      provider_account_id: [nil, "", "a" * 513, "id\0suffix", "id\nsuffix"],
      username: ["", "a" * 256, "name\0suffix"],
      display_name: ["", "a" * 256, "name\0suffix"]
    }.each do |field, values|
      values.each do |value|
        error = assert_raises(PrismHub::InputError) { build(**{field => value}) }
        assert_equal "hub.social_account.#{field}.invalid", error.code
      end
    end
  end

  def test_accepts_character_length_boundaries_without_ascii_only_identifiers
    account = build(
      provider: "a" * 64,
      provider_account_id: "і" * 512,
      username: "і" * 255,
      display_name: "і" * 255
    )

    assert_equal 512, account.provider_account_id.length
    assert_equal 255, account.username.length
    assert_equal 255, account.display_name.length
  end

  def test_owns_immutable_copies_without_freezing_caller_strings
    values = {id: +"account-1", provider: +"instagram", provider_account_id: +"ID", username: +"name", display_name: +"Name"}
    account = build(**values)

    values.each do |field, value|
      refute value.frozen?
      value << "changed"
      refute_equal value, account.public_send(field)
      assert account.public_send(field).frozen?
    end
    assert account.frozen?
  end

  private

  def build(**attributes)
    PrismHub::Domain::SocialAccount.new(
      **{id: "account-1", provider: "instagram", provider_account_id: "17841400000000000"}.merge(attributes)
    )
  end
end
