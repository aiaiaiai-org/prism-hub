# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ChannelCapabilitiesTest < Minitest::Test
  def test_normalizes_public_capabilities
    capabilities = PrismHub::Domain::ChannelCapabilities.from_hash(
      "formats" => %w[story post post],
      "text" => true,
      "media_kinds" => %w[video image]
    )

    assert_equal(
      {
        "formats" => %w[post story],
        "text" => true,
        "media_kinds" => %w[image video]
      },
      capabilities.public_attributes
    )
    assert capabilities.frozen?
  end

  def test_rejects_an_unknown_format
    error = assert_raises(PrismHub::InputError) do
      PrismHub::Domain::ChannelCapabilities.from_hash(
        "formats" => ["carousel"],
        "text" => true
      )
    end

    assert_equal "hub.channel.capabilities.formats.invalid", error.code
  end

  def test_rejects_a_channel_without_supported_content
    error = assert_raises(PrismHub::InputError) do
      PrismHub::Domain::ChannelCapabilities.from_hash(
        "formats" => ["post"],
        "text" => false,
        "media_kinds" => []
      )
    end

    assert_equal "hub.channel.capabilities.content.empty", error.code
  end
end
