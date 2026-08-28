# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    module Capabilities
      CHANNELS_READ = "channels:read".freeze
      PUBLICATIONS_VALIDATE = "publications:validate".freeze
      PUBLICATIONS_PUBLISH = "publications:publish".freeze
      ACTORS_RESOLVE = "actors:resolve".freeze
      ACTORS_ONBOARD = "actors:onboard".freeze
      BOT_INSTANCES_READ = "bot_instances:read".freeze
      BOT_INSTANCES_MANAGE = "bot_instances:manage".freeze

      ALL = [
        CHANNELS_READ,
        PUBLICATIONS_VALIDATE,
        PUBLICATIONS_PUBLISH,
        ACTORS_RESOLVE,
        ACTORS_ONBOARD,
        BOT_INSTANCES_READ,
        BOT_INSTANCES_MANAGE
      ].freeze
    end
  end
end
