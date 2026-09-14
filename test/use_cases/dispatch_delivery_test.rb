# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class DispatchDeliveryTest < Minitest::Test
  def test_resolves_the_logical_surface_and_dispatches_the_intent
    intent = build_intent
    binding = Object.new
    resolved_context = nil
    delivered = nil

    resolver = Object.new
    resolver.define_singleton_method(:call) do |workspace_id:, logical_channel:|
      resolved_context = [workspace_id, logical_channel]
      binding
    end

    gateway = Object.new
    gateway.define_singleton_method(:deliver) do |intent:, binding:|
      delivered = [intent, binding]
      :delivered
    end

    result = PrismHub::UseCases::DispatchDelivery.new(
      surface_resolver: resolver,
      delivery_gateway: gateway
    ).call(intent: intent)

    assert_equal :delivered, result
    assert_equal ["personal", "digest"], resolved_context
    assert_equal [intent, binding], delivered
  end

  def test_fails_before_routing_when_intent_is_invalid
    resolver = Object.new
    resolver.define_singleton_method(:call) { raise "must not resolve" }
    gateway = Object.new
    gateway.define_singleton_method(:deliver) { raise "must not deliver" }

    error = assert_raises(PrismHub::InputError) do
      PrismHub::UseCases::DispatchDelivery.new(
        surface_resolver: resolver,
        delivery_gateway: gateway
      ).call(intent: Object.new)
    end

    assert_equal "hub.delivery.intent.invalid", error.code
  end

  def test_propagates_surface_resolution_failures
    intent = build_intent
    error = PrismHub::TelegramSurfaceBindingNotFoundError.new(
      "hub.telegram_surface_binding.not_found",
      "missing"
    )
    resolver = Object.new
    resolver.define_singleton_method(:call) { |**| raise error }
    gateway = Object.new
    gateway.define_singleton_method(:deliver) { raise "must not deliver" }

    raised = assert_raises(PrismHub::TelegramSurfaceBindingNotFoundError) do
      PrismHub::UseCases::DispatchDelivery.new(
        surface_resolver: resolver,
        delivery_gateway: gateway
      ).call(intent: intent)
    end

    assert_same error, raised
  end

  private

  def build_intent
    chunks = [{"text" => "hello", "position" => 1, "total" => 1}]
    idempotency_key = Digest::SHA256.hexdigest([
      "mail.digest",
      "artifact-1",
      "personal",
      "digest",
      "plain_text",
      "hello"
    ].join("\0"))

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
end
