# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class PublicUserIdTest < Minitest::Test
  def test_accepts_every_canonical_symbol
    PrismHub::Domain::PublicUserId::SYMBOLS.each do |symbol|
      value = PrismHub::Domain::PublicUserId.new("0xa#{symbol}")

      assert_equal "0xa#{symbol}", value.to_s
    end
  end

  def test_accepts_slug_boundaries
    assert_equal "0xaa", PrismHub::Domain::PublicUserId.new("0xaa").to_s
    maximum = "0x#{'a' * 32}"
    assert_equal maximum, PrismHub::Domain::PublicUserId.new(maximum).to_s
  end

  def test_rejects_noncanonical_values
    invalid = [
      "0xa",
      "0x#{'a' * 33}",
      "0xA1",
      "0xа1",
      "0xa b",
      "0xa🙂",
      "0xa”",
      "a1"
    ]

    invalid.each do |value|
      error = assert_raises(PrismHub::InputError) { PrismHub::Domain::PublicUserId.new(value) }
      assert_equal "hub.user_identity.public_id.invalid", error.code
    end
  end
end
