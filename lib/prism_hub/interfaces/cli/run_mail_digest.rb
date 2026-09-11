# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Interfaces
    module Cli
      class RunMailDigest
        def initialize(generate_mail_digest:, out: $stdout, errors: $stderr)
          @generate_mail_digest = generate_mail_digest
          @out = out
          @errors = errors
        end

        def call(mailbox_id:, since:, before:)
          artifact = @generate_mail_digest.call(mailbox_id: mailbox_id, since: since, before: before)
          @out.puts(JSON.generate(artifact))
          0
        rescue PrismHub::Error => error
          @errors.puts(JSON.generate(error: {code: error.code}))
          1
        end
      end
    end
  end
end
