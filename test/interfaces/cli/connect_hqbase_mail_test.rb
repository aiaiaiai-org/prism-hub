# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../../test_helper"

class ConnectHqbaseMailCliTest < Minitest::Test
  class Connection
    def start
      {
        "client_id" => "client-prism",
        "device_code" => "device-secret",
        "user_code" => "ABCD-EFGH",
        "verification_uri" => "https://mail.aiaiaiai.org/device",
        "verification_uri_complete" => "https://mail.aiaiaiai.org/device?user_code=ABCD-EFGH",
        "expires_at" => Time.utc(2026, 9, 11, 18, 15, 0),
        "interval_seconds" => 5
      }
    end

    def complete(authorization:)
      raise "device code lost" unless authorization.fetch("device_code") == "device-secret"

      {"status" => "connected", "expires_at" => Time.utc(2026, 9, 11, 19, 0, 0)}
    end
  end

  def test_prints_approval_url_but_never_tokens
    out = StringIO.new

    status = PrismHub::Interfaces::CLI::ConnectHqbaseMail.new(connection: Connection.new, out: out).call

    assert_equal 0, status
    assert_includes out.string, "https://mail.aiaiaiai.org/device?user_code=ABCD-EFGH"
    assert_includes out.string, "ABCD-EFGH"
    refute_includes out.string, "device-secret"
    refute_includes out.string, "hqb_access_"
    refute_includes out.string, "hqb_refresh_"
  end
end
