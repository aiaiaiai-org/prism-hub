# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class ProcessDeliveryOutboxTest < Minitest::Test
  class Repository
    attr_reader :claimed, :delivered, :failed

    def initialize(entries)
      @entries = entries
      @claimed = false
    end

    def claim_due(limit:, now:, lease_seconds:)
      @claimed = [limit, now, lease_seconds]
      @entries
    end

    def mark_delivered(**attributes)
      @delivered = attributes
    end

    def mark_failed(**attributes)
      @failed = attributes
    end
  end

  class Dispatcher
    attr_reader :intent

    def initialize(error: nil)
      @error = error
    end

    def call(intent:)
      @intent = intent
      raise @error if @error
      :ok
    end
  end

  def setup
    @now = Time.utc(2026, 9, 14, 3)
    @intent = build_intent("hello")
    @entry = PrismHub::Domain::DeliveryOutboxEntry.new(
      id: "entry-1",
      workspace: "personal",
      channel: "digest",
      idempotency_key: @intent.idempotency_key,
      intent_payload: @intent.to_h,
      status: "processing",
      attempts: 1,
      available_at: @now,
      locked_at: @now,
      lock_token: "a" * 64
    )
  end

  def test_dispatches_persisted_intent_and_marks_delivery
    repository = Repository.new([@entry])
    dispatcher = Dispatcher.new
    processor = PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: repository,
      dispatch_delivery: dispatcher,
      clock: -> { @now }
    )

    processor.call(limit: 1, lease_seconds: 300)

    assert_equal @intent.to_h, dispatcher.intent.to_h
    assert_equal({id: "entry-1", lock_token: "a" * 64, delivered_at: @now}, repository.delivered)
    assert_nil repository.failed
  end

  def test_transient_delivery_failure_schedules_retry
    error = PrismHub::ExecutionUnavailableError.new(
      "hub.bot.delivery.unavailable",
      "unavailable"
    )
    repository = Repository.new([@entry])
    processor = PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: repository,
      dispatch_delivery: Dispatcher.new(error: error),
      clock: -> { @now }
    )

    processor.call(limit: 1, lease_seconds: 300)

    assert_equal "hub.bot.delivery.unavailable", repository.failed[:error_code]
    assert_equal @now + 30, repository.failed[:retry_at]
  end

  def test_rate_limit_retry_uses_provider_delay
    error = PrismHub::ExecutionUnavailableError.new(
      "hub.bot.delivery.rate_limited",
      "rate limited",
      details: {"retry_after_seconds" => 17}
    )
    repository = Repository.new([@entry])
    processor = PrismHub::UseCases::ProcessDeliveryOutbox.new(
      outbox_repository: repository,
      dispatch_delivery: Dispatcher.new(error: error),
      clock: -> { @now }
    )

    processor.call(limit: 1, lease_seconds: 300)

    assert_equal @now + 17, repository.failed[:retry_at]
  end

  private

  def build_intent(text)
    idempotency_key = Digest::SHA256.hexdigest([
      "mail.digest", "artifact-1", "personal", "digest", "plain_text", text
    ].join("\0"))
    PrismHub::Domain::DeliveryIntent.new(
      artifact_id: "artifact-1",
      artifact_kind: "mail.digest",
      workspace: "personal",
      channel: "digest",
      format: "plain_text",
      chunks: [{"text" => text, "position" => 1, "total" => 1}],
      idempotency_key: idempotency_key
    )
  end
end
