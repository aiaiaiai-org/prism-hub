# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class AuthorisationContextTest < Minitest::Test
  def test_is_immutable_and_deduplicates_grants
    context = PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-personal",
      workspace_id: "personal",
      capabilities: ["channels:read", "channels:read"],
      allowed_channel_ids: ["personal-threads", "personal-threads"]
    )

    assert context.frozen?
    assert_equal ["channels:read"], context.capabilities
    assert_equal ["personal-threads"], context.allowed_channel_ids
    assert context.allows_capability?("channels:read")
    assert context.allows_channel?("personal-threads")
    refute context.allows_channel?("private-channel")
  end
end
