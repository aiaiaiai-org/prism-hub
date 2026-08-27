# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class EnvironmentChannelRepositoryTest < Minitest::Test
  def test_pages_only_allowed_channels_in_stable_id_order
    repository = repository_with("zeta", "alpha", "middle")

    first = repository.page(limit: 1, allowed_ids: %w[zeta alpha])
    second = repository.page(
      limit: 1,
      after_id: first.next_after_id,
      allowed_ids: %w[zeta alpha]
    )

    assert_equal ["alpha"], first.channels.map(&:id)
    assert_equal "alpha", first.next_after_id
    assert_equal ["zeta"], second.channels.map(&:id)
    assert_nil second.next_after_id
  end

  def test_rejects_a_cursor_outside_the_allowed_scope
    error = assert_raises(PrismHub::InputError) do
      repository_with("alpha", "hidden").page(
        limit: 1,
        after_id: "hidden",
        allowed_ids: ["alpha"]
      )
    end

    assert_equal "hub.channels.cursor.invalid", error.code
  end

  def test_all_ids_are_stable_and_sorted_for_explicit_legacy_contexts
    repository = repository_with("zeta", "alpha")

    assert_equal %w[alpha zeta], repository.all_ids
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
