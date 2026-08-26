# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ListChannelsTest < Minitest::Test
  def test_returns_public_values_and_internal_continuation
    result = PrismHub::UseCases::ListChannels.new(
      channel_repository: PrismHubTestSupport.channels
    ).call(limit: 1)

    assert_equal "personal-threads", result.dig("channels", 0, "id")
    assert_equal ["post"], result.dig("channels", 0, "capabilities", "formats")
    assert_nil result.fetch("next_after_id")
  end
end
