# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class DeliveryRequestTest < Minitest::Test
  def test_survives_the_json_round_trip_the_outbox_performs
    request = build
    restored = PrismHub::Domain::DeliveryRequest.from_h(JSON.parse(JSON.generate(request.to_h)))

    assert_equal request.to_h, restored.to_h
    assert_equal "prism-hub.delivery-request.v1", restored.to_h.fetch("schema_version")
  end

  def test_is_immutable_and_does_not_share_mutable_input
    artifact = {"artifact_id" => "artifact-1", "artifact_kind" => "mail.digest", "payload" => {"a" => 1}}
    request = build(artifact: artifact)
    artifact["payload"]["a"] = 2

    assert_equal 1, request.artifact.fetch("payload").fetch("a")
    assert request.frozen?
    assert request.artifact.frozen?
    assert request.routes.frozen?
  end

  def test_carries_no_split_because_the_target_is_not_known_yet
    refute build.to_h.key?("chunks")
  end

  def test_rejects_a_payload_from_another_schema
    payload = build.to_h.merge("schema_version" => "prism-porter.delivery-intent.v1")
    error = assert_raises(PrismHub::InputError) { PrismHub::Domain::DeliveryRequest.from_h(payload) }

    assert_equal "hub.delivery_request.schema.invalid", error.code
  end

  def test_rejects_an_incomplete_artifact
    error = assert_raises(PrismHub::InputError) do
      build(artifact: {"artifact_id" => "artifact-1", "payload" => {}})
    end

    assert_equal "hub.delivery_request.artifact.invalid", error.code
  end

  def test_rejects_empty_routes
    error = assert_raises(PrismHub::InputError) { build(routes: []) }

    assert_equal "hub.delivery_request.routes.invalid", error.code
  end

  def test_rejects_an_idempotency_key_that_is_not_a_digest
    error = assert_raises(PrismHub::InputError) { build(idempotency_key: "artifact-1") }

    assert_equal "hub.delivery_request.idempotency_key.invalid", error.code
  end

  def test_rejects_an_operator_ceiling_outside_the_supported_range
    [0, 63, 200_000, "4096"].each do |value|
      error = assert_raises(PrismHub::InputError) { build(chunk_max_chars_limit: value) }

      assert_equal "hub.delivery_request.chunk_max_chars_limit.invalid", error.code
    end
  end

  private

  def build(**overrides)
    PrismHub::Domain::DeliveryRequest.new(
      **{
        artifact: {"artifact_id" => "artifact-1", "artifact_kind" => "mail.digest", "payload" => {"a" => 1}},
        routes: [{"artifact_kind" => "mail.digest",
                  "logical_context" => {"workspace" => "personal", "channel" => "digest"}}],
        workspace: "personal",
        channel: "digest",
        idempotency_key: Digest::SHA256.hexdigest("artifact-1")
      }.merge(overrides)
    )
  end
end
