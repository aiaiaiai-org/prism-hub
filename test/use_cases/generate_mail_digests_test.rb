# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class GenerateMailDigestsTest < Minitest::Test
  class MailboxList
    attr_reader :calls

    def initialize(mailboxes)
      @mailboxes = mailboxes
      @calls = 0
    end

    def call
      @calls += 1
      @mailboxes
    end
  end

  class Generator
    ENTRY_TIMES = {
      "mbx_one" => %w[2026-09-11T17:10:00Z 2026-09-11T17:40:00Z],
      "mbx_two" => %w[2026-09-11T17:50:00Z 2026-09-11T17:30:00Z 2026-09-11T17:20:00Z]
    }.freeze

    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(mailbox_id:, since:, before:)
      @calls << {mailbox_id: mailbox_id, since: since, before: before}
      entries = ENTRY_TIMES.fetch(mailbox_id).each_with_index.map do |received_at, index|
        {
          "kind" => "source_excerpt",
          "evidence" => {
            "id" => "#{mailbox_id}-#{index}",
            "mailbox_id" => mailbox_id,
            "subject" => "Subject #{index}",
            "sender" => "sender#{index}@example.com",
            "excerpt" => "Excerpt #{index}",
            "received_at" => received_at
          }
        }
      end

      {
        "schema_version" => "prism-mail.digest.v1",
        "mode" => "extractive",
        "mailbox_id" => mailbox_id,
        "window" => {"since" => since, "before" => before},
        "matched_count" => entries.length,
        "selected_count" => entries.length,
        "omitted_count" => 0,
        "entries" => entries
      }
    end
  end

  class WrongMailboxGenerator < Generator
    def call(**attributes)
      super.tap { |artifact| artifact["mailbox_id"] = "mbx_wrong" }
    end
  end

  class WrongEvidenceMailboxGenerator < Generator
    def call(**attributes)
      super.tap do |artifact|
        artifact.fetch("entries").fetch(0).fetch("evidence")["mailbox_id"] = "mbx_wrong"
      end
    end
  end

  def test_generates_one_newest_first_timeline_across_all_discovered_mailboxes
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
    assert_equal "extractive", artifact.fetch("mode")
    assert_equal({"since" => "2026-09-11T17:00:00Z", "before" => "2026-09-11T18:00:00Z"}, artifact.fetch("window"))
    assert_equal 20, artifact.fetch("limit")
    assert_equal 2, artifact.fetch("mailbox_count")
    assert_equal 5, artifact.fetch("matched_count")
    assert_equal 5, artifact.fetch("selected_count")
    assert_equal 0, artifact.fetch("omitted_count")
    assert_equal 5, artifact.fetch("entries").length
    assert_equal(
      %w[mbx_two-0 mbx_one-1 mbx_two-1 mbx_two-2 mbx_one-0],
      artifact.fetch("entries").map { _1.fetch("evidence").fetch("id") }
    )
    assert_equal(
      %w[mbx_two mbx_one mbx_two mbx_two mbx_one],
      artifact.fetch("entries").map { _1.fetch("mailbox").fetch("id") }
    )
    assert_equal %w[mbx_one mbx_two], artifact.fetch("digests").map { _1.fetch("mailbox").fetch("id") }
    assert_equal %w[mbx_one mbx_two], generator.calls.map { _1.fetch(:mailbox_id) }
    assert generator.calls.all? { _1.fetch(:since) == "2026-09-11T17:00:00Z" }
    assert generator.calls.all? { _1.fetch(:before) == "2026-09-11T18:00:00Z" }
  end

  def test_caps_the_global_timeline_without_changing_child_digest_provenance
    artifact = build_use_case(Generator.new, limit: 3).call(
      since: "2026-09-11T17:00:00Z",
      before: "2026-09-11T18:00:00Z"
    )

    assert_equal 3, artifact.fetch("limit")
    assert_equal 5, artifact.fetch("matched_count")
    assert_equal 3, artifact.fetch("selected_count")
    assert_equal 2, artifact.fetch("omitted_count")
    assert_equal %w[mbx_two-0 mbx_one-1 mbx_two-1], artifact.fetch("entries").map { _1.fetch("evidence").fetch("id") }
    assert_equal [2, 3], artifact.fetch("digests").map { _1.fetch("digest").fetch("selected_count") }
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
    assert_equal 3, artifact.fetch("entries").length
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

  def test_rejects_child_digest_with_wrong_mailbox_identity
    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      build_use_case(WrongMailboxGenerator.new).call(
        since: "2026-09-11T17:00:00Z",
        before: "2026-09-11T18:00:00Z",
        mailbox_ids: ["mbx_one"]
      )
    end

    assert_equal "hub.mail.digest.invalid", error.code
  end

  def test_rejects_evidence_that_crosses_the_mailbox_boundary
    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      build_use_case(WrongEvidenceMailboxGenerator.new).call(
        since: "2026-09-11T17:00:00Z",
        before: "2026-09-11T18:00:00Z",
        mailbox_ids: ["mbx_one"]
      )
    end

    assert_equal "hub.mail.digest.invalid", error.code
  end

  def test_rejects_invalid_window_before_mailbox_discovery
    mailbox_list = MailboxList.new(mailboxes)
    use_case = PrismHub::UseCases::GenerateMailDigests.new(
      list_mailboxes: mailbox_list,
      generate_mail_digest: Generator.new
    )

    error = assert_raises(PrismHub::InputError) do
      use_case.call(
        since: "2026-09-11T18:00:00Z",
        before: "2026-09-11T18:00:00Z"
      )
    end

    assert_equal "hub.mail.window.invalid", error.code
    assert_equal 0, mailbox_list.calls
  end

  def test_rejects_limit_outside_the_supported_range
    assert_raises(ArgumentError) { build_use_case(Generator.new, limit: 0) }
    assert_raises(ArgumentError) { build_use_case(Generator.new, limit: 101) }
  end

  private

  def build_use_case(generator, limit: 20)
    PrismHub::UseCases::GenerateMailDigests.new(
      list_mailboxes: MailboxList.new(mailboxes),
      generate_mail_digest: generator,
      limit: limit
    )
  end

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
