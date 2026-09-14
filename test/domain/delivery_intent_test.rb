# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class DeliveryIntentTest < Minitest::Test
  def test_builds_an_immutable_verified_delivery_intent
    intent = build_intent

    assert_equal "artifact-1", intent.artifact_id
    assert_equal "mail.digest", intent.artifact_kind
    assert_equal "personal", intent.workspace
    assert_equal "digest", intent.channel
    assert_equal "plain_text", intent.format
    assert_equal "hello world", intent.text
    assert intent.frozen?
    assert intent.chunks.frozen?
    assert intent.chunks.all?(&:frozen?)
  end

  def test_round_trips_through_versioned_payload
    intent = build_intent

    restored = PrismHub::Domain::DeliveryIntent.from_h(intent.to_h)

    assert_equal intent.to_h, restored.to_h
    assert_equal intent.idempotency_key, restored.idempotency_key
  end

  def test_rejects_unsupported_schema
    error = assert_raises(PrismHub::InputError) do
      PrismHub::Domain::DeliveryIntent.from_h("schema_version" => "prism-porter.delivery-intent.v2")
    end

    assert_equal "hub.porter.delivery_intent.payload.invalid", error.code
  end

  def test_rejects_non_sequential_chunks
    error = assert_raises(PrismHub::InputError) do
      build_intent(
        chunks: [
          {"text" => "hello ", "position" => 2, "total" => 2},
          {"text" => "world", "position" => 1, "total" => 2}
        ]
      )
    end

    assert_equal "hub.porter.delivery_intent.chunk.invalid", error.code
  end

  def test_rejects_a_forged_idempotency_key
    error = assert_raises(PrismHub::InputError) do
      build_intent(idempotency_key: "0" * 64)
    end

    assert_equal "hub.porter.delivery_intent.idempotency_key.mismatch", error.code
  end

  private

  def build_intent(chunks: default_chunks, idempotency_key: nil)
    idempotency_key ||= fingerprint(chunks)
    PrismHub::Domain::DeliveryIntent.new(
      artifact_id: "artifact-1",
      artifact_kind: "mail.digest",
      workspace: "personal",
      channel: "digest",
      format: "plain_text",
      chunks: chunks,
      idempotency_key: idempotency_key
    )
  end

  def default_chunks
    [
      {"text" => "hello ", "position" => 1, "total" => 2},
      {"text" => "world", "position" => 2, "total" => 2}
    ]
  end

  def fingerprint(chunks)
    Digest::SHA256.hexdigest([
      "mail.digest",
      "artifact-1",
      "personal",
      "digest",
      "plain_text",
      chunks.map { |chunk| chunk.fetch("text") }.join
    ].join("\0"))
  end
end
