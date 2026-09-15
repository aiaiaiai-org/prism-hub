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
    outbox = Outbox.new
    now = Time.utc(2026, 9, 14, 4)
    use_case = PrismHub::UseCases::EnqueueMailDigestDelivery.new(
      generate_mail_digest: generator,
      generate_mail_digests: generator,
      outbox_repository: outbox,
      clock: -> { now }
    )

    use_case.call(
      since: "2026-09-14T03:00:00Z",
      before: "2026-09-14T04:00:00Z",
      workspace: "personal",
      channel: "digest",
      chunk_max_chars: 2000
    )

    request = outbox.arguments.fetch(:request)
    context = request.routes.first.fetch("logical_context")

    assert_equal 1, generator.calls.length
    assert_equal "personal", context.fetch("workspace")
    assert_equal "digest", context.fetch("channel")
    assert_equal now, outbox.arguments.fetch(:available_at)
    assert_match(/\Amail-digest-[0-9a-f]{64}\z/, request.artifact.fetch("artifact_id"))
    assert_equal artifact, request.artifact.fetch("payload")
    assert_equal 2000, request.chunk_max_chars_limit
  end

  def test_enqueues_without_rendering_so_the_split_can_follow_the_target
    generator = Generator.new({"schema_version" => "prism-hub.mail-digests.v1", "entries" => []})
    outbox = Outbox.new
    PrismHub::UseCases::EnqueueMailDigestDelivery.new(
      generate_mail_digest: generator,
      generate_mail_digests: generator,
      outbox_repository: outbox,
      clock: -> { Time.utc(2026, 9, 14, 4) }
    ).call(
      since: "2026-09-14T03:00:00Z", before: "2026-09-14T04:00:00Z",
      workspace: "personal", channel: "digest"
    )

    request = outbox.arguments.fetch(:request)

    assert_instance_of PrismHub::Domain::DeliveryRequest, request
    assert_nil request.chunk_max_chars_limit
    refute request.to_h.key?("chunks"), "the queue must not carry a target-specific split"
    round_trip = PrismHub::Domain::DeliveryRequest.from_h(JSON.parse(JSON.generate(request.to_h)))
    assert_equal request.to_h, round_trip.to_h, "a queued request must survive JSON storage"
  end
end
