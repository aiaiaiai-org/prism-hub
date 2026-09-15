# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class DispatchDeliveryTest < Minitest::Test
  class Builder
    attr_reader :arguments

    def initialize(intent) = @intent = intent

    def call(**arguments)
      @arguments = arguments
      @intent
    end
  end

  Target = Struct.new(:text_max_chars)

  def test_resolves_the_surface_then_renders_within_its_limit
    intent = build_intent
    binding = Target.new(4096)
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

    builder = Builder.new(intent)
    result = PrismHub::UseCases::DispatchDelivery.new(
      surface_resolver: resolver,
      delivery_gateway: gateway,
      build_delivery_intent: builder
    ).call(request: build_request)

    assert_equal :delivered, result
    assert_equal ["personal", "digest"], resolved_context
    assert_equal [intent, binding], delivered
    assert_equal 4096, builder.arguments.fetch(:chunk_max_chars)
  end

  def test_operator_ceiling_lowers_the_surface_limit_but_never_raises_it
    binding = Target.new(4096)
    resolver = Object.new
    resolver.define_singleton_method(:call) { |**| binding }
    gateway = Object.new
    gateway.define_singleton_method(:deliver) { |**| :delivered }

    [[2000, 2000], [9000, 4096], [nil, 4096]].each do |override, expected|
      builder = Builder.new(build_intent)
      PrismHub::UseCases::DispatchDelivery.new(
        surface_resolver: resolver, delivery_gateway: gateway, build_delivery_intent: builder
      ).call(request: build_request(chunk_max_chars_limit: override))

      assert_equal expected, builder.arguments.fetch(:chunk_max_chars),
        "override #{override.inspect} must not exceed the surface limit"
    end
  end

  def test_fails_before_routing_when_the_request_is_invalid
    resolver = Object.new
    resolver.define_singleton_method(:call) { raise "must not resolve" }
    gateway = Object.new
    gateway.define_singleton_method(:deliver) { raise "must not deliver" }

    error = assert_raises(PrismHub::InputError) do
      PrismHub::UseCases::DispatchDelivery.new(
        surface_resolver: resolver,
        delivery_gateway: gateway,
        build_delivery_intent: Builder.new(build_intent)
      ).call(request: Object.new)
    end

    assert_equal "hub.delivery.request.invalid", error.code
  end

  def test_propagates_surface_resolution_failures
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
        delivery_gateway: gateway,
        build_delivery_intent: Builder.new(build_intent)
      ).call(request: build_request)
    end

    assert_same error, raised
  end

  private

  def build_request(chunk_max_chars_limit: nil)
    PrismHub::Domain::DeliveryRequest.new(
      artifact: {"artifact_id" => "artifact-1", "artifact_kind" => "mail.digest", "payload" => {"a" => 1}},
      routes: [{"artifact_kind" => "mail.digest",
                "logical_context" => {"workspace" => "personal", "channel" => "digest"}}],
      workspace: "personal",
      channel: "digest",
      idempotency_key: Digest::SHA256.hexdigest("artifact-1"),
      chunk_max_chars_limit: chunk_max_chars_limit
    )
  end

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
