# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class BotInstanceTest < Minitest::Test
  def test_accepts_coherent_paused_state
    instance = PrismHub::Domain::BotInstance.new(
      id: "instance-1",
      principal_id: "telegram-bot",
      workspace_id: "personal-a",
      status: "paused",
      paused_at: Time.utc(2026, 8, 28, 3, 30)
    )

    assert instance.paused?
    refute instance.active?
    refute instance.disabled?
    assert instance.frozen?
  end

  def test_rejects_incoherent_lifecycle_timestamps
    error = assert_raises(PrismHub::InputError) do
      PrismHub::Domain::BotInstance.new(
        id: "instance-1",
        principal_id: "telegram-bot",
        workspace_id: "personal-a",
        status: "active",
        paused_at: Time.utc(2026, 8, 28, 3, 31)
      )
    end

    assert_equal "hub.bot_instance.state.invalid", error.code
  end
end
