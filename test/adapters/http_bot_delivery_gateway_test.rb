# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class HttpBotDeliveryGatewayTest < Minitest::Test
  class FakeTransport
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def call(**request)
      @requests << request
      response = @responses.shift
      return response unless response.respond_to?(:call)

      response.call(request)
    end
  end

  def test_delivers_each_intent_chunk_to_the_bound_telegram_surface
    transport = FakeTransport.new([response_for("first"), response_for("second")])
    gateway = gateway_for(transport)
    intent = intent_for(["first", "second"])

    results = gateway.deliver(intent: intent, binding: binding_for)

    assert_equal 2, results.length
    assert_equal ["first", "second"], transport.requests.map { |request| JSON.parse(request.fetch(:body)).fetch("text") }
    assert_equal ["chat-123", "chat-123"], transport.requests.map { |request| JSON.parse(request.fetch(:body)).fetch("chat_id") }
    assert_equal [42, 42], transport.requests.map { |request| JSON.parse(request.fetch(:body)).fetch("message_thread_id") }
    assert_equal ["secret"], transport.requests.map { |request| request.fetch(:headers).fetch("x-prism-bot-delivery-secret") }.uniq
    keys = transport.requests.map { |request| JSON.parse(request.fetch(:body)).fetch("idempotency_key") }
    assert keys.all? { |key| key.match?(/\A[0-9a-f]{64}\z/) }
    refute_equal keys[0], keys[1]
  end

  def test_rejects_a_binding_for_another_logical_context
    error = assert_raises(PrismHub::InputError) do
      gateway_for(FakeTransport.new([])).deliver(intent: intent_for(["first"]), binding: binding_for(logical_channel: "other"))
    end

    assert_equal "hub.bot.delivery.context.mismatch", error.code
  end

  def test_maps_bot_rate_limit
    gateway = gateway_for(FakeTransport.new([
      {status: 429, body: JSON.generate("status" => "error", "error" => {"code" => "bot.telegram.rate_limited", "retry_after_seconds" => 3})}
    ]))

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.deliver(intent: intent_for(["first"]), binding: binding_for)
    end

    assert_equal "hub.bot.delivery.rate_limited", error.code
    assert_equal({"retry_after_seconds" => 3}, error.details)
  end

  def test_maps_transport_failure
    transport = Object.new
    def transport.call(**)
      raise SocketError, "offline"
    end
    gateway = gateway_for(transport)

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.deliver(intent: intent_for(["first"]), binding: binding_for)
    end

    assert_equal "hub.bot.delivery.unavailable", error.code
  end

  private

  def gateway_for(transport)
    PrismHub::Adapters::HttpBotDeliveryGateway.new(origin: "https://bot.example.test", secret: "secret", transport: transport)
  end

  def response_for(message_id)
    lambda do |request|
      body = JSON.parse(request.fetch(:body))
      {status: 200, body: JSON.generate("status" => "ok", "delivery" => {"provider_message_id" => message_id, "idempotency_key" => body.fetch("idempotency_key")})}
    end
  end

  def intent_for(texts)
    chunks = texts.each_with_index.map { |text, index| {"text" => text, "position" => index + 1, "total" => texts.length} }
    value = {"artifact_kind" => "mail.digest", "artifact_id" => "artifact-1", "workspace" => "workspace-1", "channel" => "digest", "format" => "plain_text", "chunks" => chunks}
    fingerprint = Digest::SHA256.hexdigest([
      value.fetch("artifact_kind"), value.fetch("artifact_id"), value.fetch("workspace"), value.fetch("channel"), value.fetch("format"), texts.join
    ].join("\0"))
    PrismHub::Domain::DeliveryIntent.new(
      artifact_id: value.fetch("artifact_id"), artifact_kind: value.fetch("artifact_kind"), workspace: value.fetch("workspace"),
      channel: value.fetch("channel"), format: value.fetch("format"), chunks: chunks, idempotency_key: fingerprint
    )
  end

  def binding_for(logical_channel: "digest")
    PrismHub::Domain::TelegramSurfaceBinding.new(
      id: "binding-1", workspace_id: "workspace-1", bot_instance_id: "bot-1", logical_channel: logical_channel,
      chat_id: "chat-123", message_thread_id: 42, created_by_user_identity_id: "user-1", status: "active"
    )
  end
end
