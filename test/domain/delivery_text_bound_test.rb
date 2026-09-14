# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class DeliveryTextBoundTest < Minitest::Test
  Target = Struct.new(:text_max_chars)

  def test_the_narrowest_target_decides_the_split
    assert_equal 1600, bound(targets: [Target.new(4096), Target.new(1600), Target.new(2400)])
  end

  def test_a_single_target_is_its_own_bound
    assert_equal 4096, bound(targets: [Target.new(4096)])
  end

  def test_an_override_may_lower_the_bound
    assert_equal 900, bound(targets: [Target.new(4096)], override: 900)
  end

  def test_an_override_may_never_raise_it_past_what_a_surface_accepts
    assert_equal 4096, bound(targets: [Target.new(4096)], override: 9000)
    assert_equal 1600, bound(targets: [Target.new(4096), Target.new(1600)], override: 4096)
  end

  def test_telegram_bindings_carry_their_own_limit
    binding = PrismHub::Domain::TelegramSurfaceBinding.new(
      id: "binding-1", workspace_id: "personal", bot_instance_id: "bot-1",
      logical_channel: "digest", chat_id: -1001,
      created_by_user_identity_id: "user-1", status: "active"
    )

    assert_equal 4096, binding.text_max_chars
    assert_equal 4096, bound(targets: [binding])
  end

  def test_without_a_target_there_is_nothing_to_size_against
    error = assert_raises(PrismHub::InputError) { bound(targets: []) }

    assert_equal "hub.delivery.text_bound.targets.missing", error.code
  end

  def test_a_target_without_a_usable_limit_is_rejected
    [Target.new(nil), Target.new("4096"), Target.new(0), Target.new(200_000), Object.new].each do |target|
      error = assert_raises(PrismHub::InputError) { bound(targets: [target]) }

      assert_equal "hub.delivery.text_bound.target.invalid", error.code
    end
  end

  def test_a_malformed_override_is_rejected_rather_than_ignored
    ["900", 0, 200_000, 4.5].each do |override|
      error = assert_raises(PrismHub::InputError) do
        bound(targets: [Target.new(4096)], override: override)
      end

      assert_equal "hub.delivery.text_bound.override.invalid", error.code
    end
  end

  private

  def bound(targets:, override: nil)
    PrismHub::Domain::DeliveryTextBound.for(targets: targets, override: override)
  end
end
