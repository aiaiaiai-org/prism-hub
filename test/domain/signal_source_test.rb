# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class SignalSourceTest < Minitest::Test
  def list(**settings)
    PrismHub::Domain::SignalSource.list_from(**settings)
  end

  def test_a_channel_list_names_public_telegram_channels
    sources = list(telegram_channels: " vanek_nikolaev, other_channel ,")

    assert_equal %w[telegram.channel:vanek_nikolaev telegram.channel:other_channel], sources.map(&:id)
  end

  def test_the_json_form_still_works
    sources = list(sources_json: '[{"kind":"telegram","channel":"vanek_nikolaev"}]')

    assert_equal ["telegram.channel:vanek_nikolaev"], sources.map(&:id)
  end

  def test_exactly_one_setting_is_required
    [{}, {telegram_channels: " "}, {telegram_channels: "a_channel", sources_json: "[]"}].each do |settings|
      error = assert_raises(PrismHub::ConfigurationError, settings.inspect) { list(**settings) }
      assert_equal "hub.signal.sources.invalid", error.code
    end
  end

  def test_bad_sources_are_refused
    [
      {telegram_channels: ","},
      {telegram_channels: "vanek_nikolaev,vanek_nikolaev"},
      {telegram_channels: "--after"},
      {sources_json: "{"},
      {sources_json: "{}"},
      {sources_json: "[]"}
    ].each do |settings|
      assert_raises(PrismHub::ConfigurationError, settings.inspect) { list(**settings) }
    end
  end
end
