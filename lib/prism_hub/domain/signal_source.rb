# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    # A place the hub reads reports from. Only public Telegram channels for now.
    #
    # The channel name goes to a subprocess as an argument, so it is held to what Telegram allows
    # for a public username and can never look like a flag.
    class SignalSource
      KINDS = %w[telegram].freeze
      CHANNEL_PATTERN = /\A[A-Za-z][A-Za-z0-9_]{3,31}\z/

      attr_reader :kind, :channel

      def self.from_h(value)
        unless value.is_a?(Hash) && value.keys.sort == %w[channel kind]
          raise ConfigurationError.new(
            "hub.signal.source.invalid",
            "a signal source is an object with exactly kind and channel"
          )
        end

        new(kind: value["kind"], channel: value["channel"])
      end

      def initialize(kind:, channel:)
        unless KINDS.include?(kind)
          raise ConfigurationError.new(
            "hub.signal.source.kind.invalid",
            "signal source kind must be one of #{KINDS.join(", ")}"
          )
        end
        unless channel.is_a?(String) && CHANNEL_PATTERN.match?(channel)
          raise ConfigurationError.new(
            "hub.signal.source.channel.invalid",
            "signal source channel must be a public channel username"
          )
        end

        @kind = kind.dup.freeze
        @channel = channel.dup.freeze
        freeze
      end

      # The identifier the collector puts in every piece of evidence it emits.
      def id
        "#{kind}.channel:#{channel}"
      end
    end
  end
end
