# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../../test_helper"

class RunMailDigestCliTest < Minitest::Test
  class Generator
    def call(mailbox_id:, since:, before:)
      raise "wrong mailbox" unless mailbox_id == "mailbox-1"
      raise "wrong since" unless since == "2026-09-11T17:00:00Z"
      raise "wrong before" unless before == "2026-09-11T18:00:00Z"

      {
        "schema_version" => "prism-mail.digest.v1",
        "mode" => "extractive",
        "mailbox_id" => mailbox_id,
        "window" => {"since" => since, "before" => before},
        "matched_count" => 0,
        "selected_count" => 0,
        "omitted_count" => 0,
        "entries" => []
      }
    end
  end

  class BatchGenerator
    def call(since:, before:)
      raise "wrong since" unless since == "2026-09-11T17:00:00Z"
      raise "wrong before" unless before == "2026-09-11T18:00:00Z"

      {
        "schema_version" => "prism-hub.mail-digests.v1",
        "mode" => "extractive",
        "window" => {"since" => since, "before" => before},
        "mailbox_count" => 2,
        "matched_count" => 0,
        "selected_count" => 0,
        "omitted_count" => 0,
        "digests" => []
      }
    end
  end

  class FailingGenerator
    def call(**)
      raise PrismHub::CredentialNotFoundError.new(
        "hub.mail.credential.not_found",
        "credential missing"
      )
    end
  end

  def test_writes_only_single_mailbox_digest_json_to_stdout
    out = StringIO.new
    errors = StringIO.new
    cli = PrismHub::Interfaces::Cli::RunMailDigest.new(
      generate_mail_digest: Generator.new,
      generate_mail_digests: BatchGenerator.new,
      out: out,
      errors: errors
    )

    status = cli.call(
      mailbox_id: "mailbox-1",
      since: "2026-09-11T17:00:00Z",
      before: "2026-09-11T18:00:00Z"
    )

    assert_equal 0, status
    artifact = JSON.parse(out.string)
    assert_equal "prism-mail.digest.v1", artifact.fetch("schema_version")
    assert_empty errors.string
  end

  def test_uses_multi_mailbox_digest_when_mailbox_id_is_omitted
    out = StringIO.new
    errors = StringIO.new
    cli = PrismHub::Interfaces::Cli::RunMailDigest.new(
      generate_mail_digest: Generator.new,
      generate_mail_digests: BatchGenerator.new,
      out: out,
      errors: errors
    )

    status = cli.call(
      mailbox_id: nil,
      since: "2026-09-11T17:00:00Z",
      before: "2026-09-11T18:00:00Z"
    )

    assert_equal 0, status
    artifact = JSON.parse(out.string)
    assert_equal "prism-hub.mail-digests.v1", artifact.fetch("schema_version")
    assert_equal 2, artifact.fetch("mailbox_count")
    assert_empty errors.string
  end

  def test_reports_only_typed_error_code
    out = StringIO.new
    errors = StringIO.new
    cli = PrismHub::Interfaces::Cli::RunMailDigest.new(
      generate_mail_digest: FailingGenerator.new,
      generate_mail_digests: BatchGenerator.new,
      out: out,
      errors: errors
    )

    status = cli.call(
      mailbox_id: "mailbox-1",
      since: "2026-09-11T17:00:00Z",
      before: "2026-09-11T18:00:00Z"
    )

    assert_equal 1, status
    assert_empty out.string
    assert_equal({"error" => {"code" => "hub.mail.credential.not_found"}}, JSON.parse(errors.string))
  end
end
