# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Interfaces
    module CLI
      class ConnectHqbaseMail
        def initialize(connection:, out: $stdout)
          @connection = connection
          @out = out
        end

        def call
          authorization = @connection.start
          @out.puts("Open this URL in a browser you control and approve mail:read access:")
          @out.puts(authorization.fetch("verification_uri_complete"))
          @out.puts("Code: #{authorization.fetch("user_code")}")
          @out.puts("Waiting for approval. No access or refresh token will be printed.")

          result = @connection.complete(authorization: authorization)
          @out.puts("HQBase Mail connected. Credential stored encrypted at rest.")
          if result.fetch("expires_at")
            @out.puts("Access token expires at: #{result.fetch("expires_at").iso8601}")
          end
          0
        rescue PrismHub::Error => error
          @out.puts("Connection failed: #{error.code}")
          1
        end
      end
    end
  end
end
