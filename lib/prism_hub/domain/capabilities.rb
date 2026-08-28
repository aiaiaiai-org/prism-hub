# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    module Capabilities
      CHANNELS_READ = "channels:read".freeze
      PUBLICATIONS_VALIDATE = "publications:validate".freeze
      PUBLICATIONS_PUBLISH = "publications:publish".freeze
      ACTORS_RESOLVE = "actors:resolve".freeze
      ACTORS_ONBOARD = "actors:onboard".freeze

      ALL = [
        CHANNELS_READ,
        PUBLICATIONS_VALIDATE,
        PUBLICATIONS_PUBLISH,
        ACTORS_RESOLVE,
        ACTORS_ONBOARD
      ].freeze
    end
  end
end
