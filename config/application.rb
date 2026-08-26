# © 2026 aiaiaiai · aiaiaiai.org

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module PrismHub
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.autoload_lib(ignore: %w[assets tasks])
    config.active_record.schema_format = :sql
    config.active_support.escape_html_entities_in_json = true
  end
end
