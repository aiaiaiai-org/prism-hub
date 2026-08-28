# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class SocialAccountTest < Minitest::Test
  def test_stable_provider_account_identity_is_separate_from_display_metadata
    account = PrismHub::Domain::SocialAccount.new(
      id: "account-1",
      provider: "instagram",
      provider_account_id: "17841400000000000",
      username: "old_handle",
      display_name: "Display Name"
    )

    assert_equal "instagram", account.provider
    assert_equal "17841400000000000", account.provider_account_id
    assert_equal "old_handle", account.username
    assert_equal "Display Name", account.display_name
  end

  def test_rejects_invalid_provider_and_empty_provider_account_id
    assert_raises(PrismHub::InputError) do
      PrismHub::Domain::SocialAccount.new(
        id: "account-1",
        provider: "Instagram",
        provider_account_id: "17841400000000000"
      )
    end

    assert_raises(PrismHub::InputError) do
      PrismHub::Domain::SocialAccount.new(
        id: "account-1",
        provider: "instagram",
        provider_account_id: ""
      )
    end
  end
end
