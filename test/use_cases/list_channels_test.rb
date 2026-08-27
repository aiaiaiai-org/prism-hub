# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ListChannelsTest < Minitest::Test
  def test_returns_only_channels_granted_to_the_principal
    result = PrismHub::UseCases::ListChannels.new(
      channel_repository: PrismHubTestSupport.channels
    ).call(
      authorisation_context: context(
        capabilities: [PrismHub::Domain::Capabilities::CHANNELS_READ],
        channels: ["personal-threads"]
      ),
      limit: 1
    )

    assert_equal "personal-threads", result.dig("channels", 0, "id")
    assert_equal ["post"], result.dig("channels", 0, "capabilities", "formats")
    assert_nil result.fetch("next_after_id")
  end

  def test_requires_channels_read_capability
    error = assert_raises(PrismHub::AuthorisationError) do
      PrismHub::UseCases::ListChannels.new(
        channel_repository: PrismHubTestSupport.channels
      ).call(
        authorisation_context: context(capabilities: [], channels: ["personal-threads"]),
        limit: 1
      )
    end

    assert_equal "hub.authorization.capability_denied", error.code
  end

  private

  def context(capabilities:, channels:)
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-personal",
      workspace_id: "personal",
      capabilities: capabilities,
      allowed_channel_ids: channels
    )
  end
end
