# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class GenerateMailDigestsTest < Minitest::Test
  class MailboxList
    def initialize(mailboxes)
      @mailboxes = mailboxes
    end

    def call
      @mailboxes
    end
  end

  class Generator
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(mailbox_id:, since:, before:)
      @calls << {mailbox_id: mailbox_id, since: since, before: before}
      matched = mailbox_id == "mbx_one" ? 2 : 3
      {
        "schema_version" => "prism-mail.digest.v1",
        "mode" => "extractive",
        "mailbox_id" => mailbox_id,
        "window" => {"since" => "2026-09-11T17:00:00Z", "before" => "2026-09-11T18:00:00Z"},
        "matched_count" => matched,
        "selected_count" => matched,
        "omitted_count" => 0,
        "entries" => []
      }
    end
  end

  def test_generates_one_aggregate_across_all_discovered_mailboxes
    generator = Generator.new
    use_case = PrismHub::UseCases::GenerateMailDigests.new(
      list_mailboxes: MailboxList.new(mailboxes),
      generate_mail_digest: generator
    )

    artifact = use_case.call(
      since: "2026-09-11T20:00:00+03:00",
      before: "2026-09-11T21:00:00+03:00"
    )

    assert_equal "prism-hub.mail-digests.v1", artifact.fetch("schema_version")
    assert_equal 2, artifact.fetch("mailbox_count")
    assert_equal 5, artifact.fetch("matched_count")
    assert_equal 5, artifact.fetch("selected_count")
    assert_equal 0, artifact.fetch("omitted_count")
    assert_equal %w[mbx_one mbx_two], artifact.fetch("digests").map { _1.fetch("mailbox").fetch("id") }
    assert_equal %w[mbx_one mbx_two], generator.calls.map { _1.fetch(:mailbox_id) }
  end

  def test_can_select_an_explicit_subset_without_losing_discovery_authorisation
    generator = Generator.new
    use_case = PrismHub::UseCases::GenerateMailDigests.new(
      list_mailboxes: MailboxList.new(mailboxes),
      generate_mail_digest: generator
    )

    artifact = use_case.call(
      since: "2026-09-11T17:00:00Z",
      before: "2026-09-11T18:00:00Z",
      mailbox_ids: ["mbx_two"]
    )

    assert_equal 1, artifact.fetch("mailbox_count")
    assert_equal ["mbx_two"], generator.calls.map { _1.fetch(:mailbox_id) }
  end

  def test_rejects_a_mailbox_that_is_not_visible_to_connected_credential
    use_case = PrismHub::UseCases::GenerateMailDigests.new(
      list_mailboxes: MailboxList.new(mailboxes),
      generate_mail_digest: Generator.new
    )

    error = assert_raises(PrismHub::InputError) do
      use_case.call(
        since: "2026-09-11T17:00:00Z",
        before: "2026-09-11T18:00:00Z",
        mailbox_ids: ["mbx_hidden"]
      )
    end

    assert_equal "hub.mail.mailbox.not_found", error.code
  end

  private

  def mailboxes
    [
      PrismHub::Domain::Mailbox.new(
        id: "mbx_one",
        address: "one@aiaiaiai.org",
        display_name: "One",
        is_active: true,
        access_level: "manager"
      ),
      PrismHub::Domain::Mailbox.new(
        id: "mbx_two",
        address: "two@aiaiaiai.org",
        display_name: "Two",
        is_active: true,
        access_level: "manager"
      )
    ]
  end
end
