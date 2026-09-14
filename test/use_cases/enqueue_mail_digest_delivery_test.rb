# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class EnqueueMailDigestDeliveryTest < Minitest::Test
  class Generator
    attr_reader :calls

    def initialize(artifact)
      @artifact = artifact
      @calls = []
    end

    def call(**arguments)
      @calls << arguments
      @artifact
    end
  end

  class Builder
    attr_reader :arguments

    def call(**arguments)
      @arguments = arguments
      build_intent(arguments.fetch(:artifact), arguments.fetch(:routes).first.fetch("logical_context"))
    end

    private

    def build_intent(artifact, context)
      text = JSON.generate(artifact.fetch("payload"))
      key = Digest::SHA256.hexdigest([
        artifact.fetch("artifact_kind"), artifact.fetch("artifact_id"), context.fetch("workspace"),
        context.fetch("channel"), "plain_text", text
      ].join("\0"))
      PrismHub::Domain::DeliveryIntent.new(
        artifact_id: artifact.fetch("artifact_id"),
        artifact_kind: artifact.fetch("artifact_kind"),
        workspace: context.fetch("workspace"),
        channel: context.fetch("channel"),
        format: "plain_text",
        chunks: [{"text" => text, "position" => 1, "total" => 1}],
        idempotency_key: key
      )
    end
  end

  class Outbox
    attr_reader :arguments

    def enqueue(**arguments)
      @arguments = arguments
      :enqueued
    end
  end

  def test_generates_all_mailboxes_builds_logical_route_and_enqueues
    artifact = {"schema_version" => "prism-hub.mail-digests.v1", "entries" => []}
    generator = Generator.new(artifact)
    builder = Builder.new
    outbox = Outbox.new
    now = Time.utc(2026, 9, 14, 4)
    use_case = PrismHub::UseCases::EnqueueMailDigestDelivery.new(
      generate_mail_digest: generator,
      generate_mail_digests: generator,
      build_delivery_intent: builder,
      outbox_repository: outbox,
      clock: -> { now }
    )

    use_case.call(
      since: "2026-09-14T03:00:00Z",
      before: "2026-09-14T04:00:00Z",
      workspace: "personal",
      channel: "digest"
    )

    assert_equal 1, generator.calls.length
    assert_equal "personal", builder.arguments.fetch(:routes).first.fetch("logical_context").fetch("workspace")
    assert_equal "digest", builder.arguments.fetch(:routes).first.fetch("logical_context").fetch("channel")
    assert_equal now, outbox.arguments.fetch(:available_at)
    assert_match(/\Amail-digest-[0-9a-f]{64}\z/, outbox.arguments.fetch(:intent).artifact_id)
  end
end
