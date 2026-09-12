# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Interfaces
    module Cli
      class ListMailboxes
        def initialize(list_mailboxes:, out: $stdout, errors: $stderr)
          @list_mailboxes = list_mailboxes
          @out = out
          @errors = errors
        end

        def call
          mailboxes = @list_mailboxes.call
          @out.puts(
            JSON.generate(
              "schema_version" => "prism-hub.mailboxes.v1",
              "mailboxes" => mailboxes.map(&:public_attributes)
            )
          )
          0
        rescue PrismHub::Error => error
          @errors.puts(JSON.generate(error: {code: error.code}))
          1
        end
      end
    end
  end
end
