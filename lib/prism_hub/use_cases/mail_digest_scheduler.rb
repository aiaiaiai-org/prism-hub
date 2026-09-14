# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class MailDigestScheduler
      def initialize(command:, interval_seconds:, window_seconds:, clock: -> { Time.now.utc }, runner: ->(command, env) { system(env, *command) }, sleeper: ->(seconds) { sleep(seconds) })
        @command = Array(command).dup.freeze
        @interval_seconds = positive_number(interval_seconds, "interval")
        @window_seconds = positive_number(window_seconds, "window")
        @clock = clock
        @runner = runner
        @sleeper = sleeper
      end

      def run_once
        before = @clock.call.utc
        since = before - @window_seconds
        @runner.call(@command, {
          "PRISM_MAIL_SINCE" => since.iso8601,
          "PRISM_MAIL_BEFORE" => before.iso8601
        })
      end

      def run
        loop do
          run_once
          @sleeper.call(@interval_seconds)
        end
      end

      private

      def positive_number(value, name)
        number = Float(value)
        return number if number.positive?

        raise PrismHub::ConfigurationError.new(
          "hub.mail.digest.scheduler.#{name}.invalid",
          "#{name} seconds must be a positive number"
        )
      rescue ArgumentError, TypeError
        raise PrismHub::ConfigurationError.new(
          "hub.mail.digest.scheduler.#{name}.invalid",
          "#{name} seconds must be a positive number"
        )
      end
    end
  end
end
