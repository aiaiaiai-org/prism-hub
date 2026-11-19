# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class AisEnvironmentTest < Minitest::Test
  SETTING = "PRISM_HUB_DEVELOPMENT_AIS_ISSUER".freeze

  def test_production_pins_its_issuer
    assert_equal "https://auth.aiaiaiai.org", issuer({"RAILS_ENV" => "production"})
    assert_equal "https://auth.aiaiaiai.org", issuer({"RACK_ENV" => "production"})
    assert_raises(PrismHub::ConfigurationError) do
      issuer({"RAILS_ENV" => "production", SETTING => "https://ais-dev.example"})
    end
  end

  def test_development_never_falls_back_to_production
    assert_nil issuer({})
    %w[development test].each do |environment|
      assert_nil issuer({"RAILS_ENV" => environment})
      assert_equal "https://ais-dev.example",
        issuer({"RAILS_ENV" => environment, SETTING => "https://ais-dev.example"})
    end
  end

  def test_refuses_production_and_noncanonical_origins
    %w[
      https://auth.aiaiaiai.org
      https://AUTH.aiaiaiai.org
      https://auth.aiaiaiai.org.
      https://ais-dev.example/path
      https://ais-dev.example?query
      https://ais-dev.example@auth.aiaiaiai.org
      http://ais-dev.example
    ].each do |origin|
      assert_raises(PrismHub::ConfigurationError, origin) do
        issuer({"RAILS_ENV" => "development", SETTING => origin})
      end
    end
  end

  private

  def issuer(env)
    PrismHub::Bootstrap.send(:product_issuer, env)
  end
end
