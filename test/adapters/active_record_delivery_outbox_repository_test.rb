# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordDeliveryOutboxRepositoryTest < Minitest::Test
  def setup
    clear_tables
    @repository = PrismHub::Adapters::ActiveRecordDeliveryOutboxRepository.new
    @now = Time.utc(2026, 9, 14, 2, 0)
  end

  def teardown
    clear_tables
  end

  def test_enqueue_is_idempotent_by_delivery_intent_fingerprint
    intent = build_intent("hello")

    first = @repository.enqueue(intent: intent, available_at: @now)
    second = @repository.enqueue(intent: intent, available_at: @now + 60)

    assert_equal first.id, second.id
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::DeliveryOutboxEntry.count
    assert_equal @now, first.available_at
  end

  def test_claim_increments_attempts_and_uses_a_lease_token
    intent = build_intent("hello")
    entry = @repository.enqueue(intent: intent, available_at: @now)

    claimed = @repository.claim_due(limit: 1, now: @now, lease_seconds: 300)

    assert_equal [entry.id], claimed.map(&:id)
    assert_equal "processing", claimed.first.status
    assert_equal 1, claimed.first.attempts
    assert_match(/\A[0-9a-f]{64}\z/, claimed.first.lock_token)
    refute_nil claimed.first.locked_at
  end

  def test_expired_processing_lease_can_be_reclaimed
    intent = build_intent("hello")
    @repository.enqueue(intent: intent, available_at: @now)
    first = @repository.claim_due(limit: 1, now: @now, lease_seconds: 300).first

    second = @repository.claim_due(limit: 1, now: @now + 301, lease_seconds: 300).first

    assert_equal first.id, second.id
    assert_equal 2, second.attempts
    refute_equal first.lock_token, second.lock_token
  end

  def test_delivery_requires_the_current_lease_token
    intent = build_intent("hello")
    @repository.enqueue(intent: intent, available_at: @now)
    claimed = @repository.claim_due(limit: 1, now: @now, lease_seconds: 300).first

    error = assert_raises(PrismHub::InputError) do
      @repository.mark_delivered(
        id: claimed.id,
        lock_token: "b" * 64,
        delivered_at: @now + 1
      )
    end

    assert_equal "hub.delivery_outbox.lock.invalid", error.code
  end

  def test_failure_can_schedule_a_retry
    intent = build_intent("hello")
    @repository.enqueue(intent: intent, available_at: @now)
    claimed = @repository.claim_due(limit: 1, now: @now, lease_seconds: 300).first
    retry_at = @now + 60

    failed = @repository.mark_failed(
      id: claimed.id,
      lock_token: claimed.lock_token,
      failed_at: @now + 1,
      retry_at: retry_at,
      error_code: "hub.bot.delivery.unavailable",
      error_details: {"retryable" => true}
    )

    assert_equal "pending", failed.status
    assert_equal retry_at, failed.available_at
    assert_equal "hub.bot.delivery.unavailable", failed.last_error_code
    assert_equal({"retryable" => true}, failed.last_error_details)
  end

  private

  def build_intent(text)
    idempotency_key = Digest::SHA256.hexdigest([
      "mail.digest", "artifact-#{text}", "personal", "digest", "plain_text", text
    ].join("\0"))
    PrismHub::Domain::DeliveryIntent.new(
      artifact_id: "artifact-#{text}",
      artifact_kind: "mail.digest",
      workspace: "personal",
      channel: "digest",
      format: "plain_text",
      chunks: [{"text" => text, "position" => 1, "total" => 1}],
      idempotency_key: idempotency_key
    )
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    connection.execute("DELETE FROM delivery_outbox_entries") if connection.data_source_exists?("delivery_outbox_entries")
  end
end
