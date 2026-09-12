# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class ListMailboxesCliTest < Minitest::Test
  class ListMailboxes
    def call
      [
        PrismHub::Domain::Mailbox.new(
          id: "mbx_prism",
          address: "prism@aiaiaiai.org",
          display_name: "Prism",
          is_active: true,
          access_level: "manager"
        )
      ]
    end
  end

  def test_writes_discovered_mailboxes_as_json
    out = StringIO.new
    errors = StringIO.new
    status = PrismHub::Interfaces::Cli::ListMailboxes.new(
      list_mailboxes: ListMailboxes.new,
      out: out,
      errors: errors
    ).call

    assert_equal 0, status
    artifact = JSON.parse(out.string)
    assert_equal "prism-hub.mailboxes.v1", artifact.fetch("schema_version")
    assert_equal "prism@aiaiaiai.org", artifact.fetch("mailboxes").fetch(0).fetch("address")
    assert_empty errors.string
  end
end
