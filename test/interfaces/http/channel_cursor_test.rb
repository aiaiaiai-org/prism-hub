# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class ChannelCursorTest < Minitest::Test
  def test_round_trips_a_channel_id
    cursor = PrismHub::Interfaces::Http::ChannelCursor.new

    assert_equal "personal-threads", cursor.decode(cursor.encode("personal-threads"))
  end

  def test_rejects_an_invalid_cursor
    cursor = PrismHub::Interfaces::Http::ChannelCursor.new

    error = assert_raises(PrismHub::InputError) { cursor.decode("not-base64!") }

    assert_equal "hub.channels.cursor.invalid", error.code
  end
end
