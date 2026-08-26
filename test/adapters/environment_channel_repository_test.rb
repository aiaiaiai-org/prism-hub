# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class EnvironmentChannelRepositoryTest < Minitest::Test
  def test_pages_channels_in_stable_id_order
    repository = repository_with("zeta", "alpha", "middle")

    first = repository.page(limit: 2)
    second = repository.page(limit: 2, after_id: first.next_after_id)

    assert_equal %w[alpha middle], first.channels.map(&:id)
    assert_equal "middle", first.next_after_id
    assert_equal ["zeta"], second.channels.map(&:id)
    assert_nil second.next_after_id
  end

  def test_rejects_a_cursor_for_an_unknown_channel
    error = assert_raises(PrismHub::InputError) do
      repository_with("alpha").page(limit: 1, after_id: "missing")
    end

    assert_equal "hub.channels.cursor.invalid", error.code
  end

  private

  def repository_with(*ids)
    PrismHub::Adapters::EnvironmentChannelRepository.new(
      JSON.generate(ids.map { |id| channel(id) })
    )
  end

  def channel(id)
    {
      "id" => id,
      "label" => id.capitalize,
      "provider_id" => "meta.threads",
      "channel_ref" => id,
      "capabilities" => {
        "formats" => ["post"],
        "text" => true,
        "media_kinds" => []
      }
    }
  end
end
