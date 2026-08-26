# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ChannelTest < Minitest::Test
  def test_public_attributes_never_expose_binding_references
    channel = PrismHubTestSupport.channels.all.first

    assert_equal(
      {
        "id" => "personal-threads",
        "label" => "Personal Threads",
        "provider_id" => "meta.threads"
      },
      channel.public_attributes
    )
    refute_includes channel.public_attributes.keys, "credential_ref"
    refute_includes channel.public_attributes.keys, "channel_ref"
  end

  def test_prism_target_expands_server_side_binding
    channel = PrismHubTestSupport.channels.all.first

    assert_equal "0x0sky", channel.prism_target(
      target_id: "target-1",
      selection: {"mode" => "exact", "variant_id" => "variant-1"}
    ).fetch("channel")
  end
end
