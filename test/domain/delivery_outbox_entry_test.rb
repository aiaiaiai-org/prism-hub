# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class DeliveryOutboxEntryTest < Minitest::Test
  def test_the_persisted_payload_cannot_be_rewritten_after_construction
    entry = PrismHub::Domain::DeliveryOutboxEntry.new(
      id: "outbox-1", workspace: "personal", channel: "digest",
      idempotency_key: "0" * 64,
      intent_payload: {"schema_version" => "prism-hub.delivery-request.v1",
                       "artifact" => {"payload" => {"entries" => [{"subject" => "one"}]}}},
      status: "pending", attempts: 0, available_at: Time.utc(2026, 9, 14, 2)
    )

    assert_raises(FrozenError) { entry.intent_payload["artifact"]["payload"]["entries"].first["subject"] = "two" }
    assert_raises(FrozenError) { entry.intent_payload["artifact"]["payload"]["entries"] << {} }
    assert_equal "one", entry.intent_payload.dig("artifact", "payload", "entries", 0, "subject")
  end

  def test_accepts_pending_entry_without_lock
    entry = PrismHub::Domain::DeliveryOutboxEntry.new(
      id: "entry-1",
      workspace: "personal",
      channel: "digest",
      idempotency_key: "a" * 64,
      intent_payload: {"schema_version" => "prism-porter.delivery-intent.v1"},
      status: "pending",
      attempts: 0,
      available_at: Time.utc(2026, 9, 14, 2)
    )

    assert entry.due?(now: Time.utc(2026, 9, 14, 2))
    refute entry.processing?
  end

  def test_requires_lock_metadata_for_processing_entry
    error = assert_raises(PrismHub::InputError) do
      PrismHub::Domain::DeliveryOutboxEntry.new(
        id: "entry-1",
        workspace: "personal",
        channel: "digest",
        idempotency_key: "a" * 64,
        intent_payload: {"schema_version" => "prism-porter.delivery-intent.v1"},
        status: "processing",
        attempts: 1,
        available_at: Time.now.utc
      )
    end

    assert_equal "hub.delivery_outbox.state.invalid", error.code
  end
end
