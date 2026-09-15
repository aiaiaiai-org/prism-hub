# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class DeepFreezeTest < Minitest::Test
  def test_freezes_every_level_not_only_the_outer_container
    value = PrismHub::Domain::DeepFreeze.call(
      {"a" => {"b" => [{"c" => +"text"}]}, "list" => [+"one", [+"two"]]}
    )

    assert value.frozen?
    assert value.fetch("a").frozen?
    assert value.fetch("a").fetch("b").frozen?
    assert value.fetch("a").fetch("b").first.frozen?
    assert value.fetch("a").fetch("b").first.fetch("c").frozen?
    assert value.fetch("list").first.frozen?
    assert value.fetch("list").last.first.frozen?
  end

  def test_freezes_values_that_are_false_or_nil_without_stopping_early
    value = PrismHub::Domain::DeepFreeze.call({"off" => false, "none" => nil, "after" => {"x" => +"y"}})

    assert value.fetch("after").frozen?, "a falsey value must not end the walk"
    assert value.fetch("after").fetch("x").frozen?
  end

  def test_returns_the_same_object_it_was_given
    original = {"a" => 1}

    assert_same original, PrismHub::Domain::DeepFreeze.call(original)
  end
end
