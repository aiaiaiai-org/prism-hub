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
    assert_equal [123, 123], transport.requests.map { |request| JSON.parse(request.fetch(:body)).fetch("chat_id") }
    assert_equal [42, 42], transport.requests.map { |request| JSON.parse(request.fetch(:body)).fetch("message_thread_id") }
    assert_equal ["secret"], transport.requests.map { |request| request.fetch(:headers).fetch("x-prism-bot-delivery-secret") }.uniq
    keys = transport.requests.map { |request| JSON.parse(request.fetch(:body)).fetch("idempotency_key") }
    assert keys.all? { |key| key.match?(/\A[0-9a-f]{64}\z/) }
    refute_equal keys[0], keys[1]
  end

  def test_a_view_edits_deletes_and_silences_through_the_bot_contract
    transport = FakeTransport.new([response_for(77), response_for(78)])
    gateway = gateway_for(transport)
    view = PrismHub::Domain::DeliveryView.new(edit_message_id: 77, delete_message_ids: [70, 71], silent: true, slot: "board", revision: 3)

    results = gateway.deliver(intent: intent_for(["board"]), binding: binding_for, view: view)
    gateway.deliver(intent: intent_for(["plain"]), binding: binding_for)

    body = JSON.parse(transport.requests[0].fetch(:body))
    assert_equal 77, body.fetch("edit_message_id")
    assert_equal [70, 71], body.fetch("delete_message_ids")
    assert_equal true, body.fetch("silent")
    refute body.key?("slot"), "the slot is the hub's, not the bot's"
    assert_equal 77, results.last.fetch("provider_message_id")
    plain = JSON.parse(transport.requests[1].fetch(:body))
    assert_equal %w[chat_id idempotency_key message_thread_id text], plain.keys.sort
  end

  def test_a_view_needs_exactly_one_chunk
    view = PrismHub::Domain::DeliveryView.new(edit_message_id: 5)
    error = assert_raises(PrismHub::InputError) do
      gateway_for(FakeTransport.new([])).deliver(intent: intent_for(["a", "b"]), binding: binding_for, view: view)
    end

    assert_equal "hub.bot.delivery.view.multi_chunk", error.code
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

  def test_delivery_prefix_preserves_origin_payload_authentication_and_idempotency
    requests = ["", "/hua-bot"].map do |prefix|
      transport = FakeTransport.new([response_for("sent")])
      gateway = PrismHub::Adapters::HttpBotDeliveryGateway.new(
        origin: "https://api.example.test", secret: "secret", path_prefix: prefix, transport: transport
      )
      gateway.deliver(intent: intent_for(["test notification"]), binding: binding_for)
      transport.requests.fetch(0)
    end
    assert_equal "https://api.example.test/api/v1/delivery", requests[0].fetch(:uri).to_s
    assert_equal "https://api.example.test/hua-bot/api/v1/delivery", requests[1].fetch(:uri).to_s
    assert_equal requests[0].fetch(:body), requests[1].fetch(:body)
    assert_equal requests[0].fetch(:headers), requests[1].fetch(:headers)
  end

  def test_rejects_noncanonical_delivery_prefixes_before_transport
    [nil, 12, "/", "hua-bot", "/hua-bot/", "//host", "/../bot", "/a/./b",
      "/a%2fb", "/a?b", "/a#b", "/a\\\\b", "/a\n", "/" + "a" * 200].each do |prefix|
      transport = FakeTransport.new([])
      error = assert_raises(PrismHub::ConfigurationError) do
        PrismHub::Adapters::HttpBotDeliveryGateway.new(
          origin: "https://api.example.test", secret: "secret", path_prefix: prefix, transport: transport
        )
      end
      assert_equal "hub.bot.path_prefix.invalid", error.code
      assert_empty transport.requests
    end
  end

  def test_prefix_does_not_relax_https_origin_validation
    ["http://api.example.test", "https://api.example.test/hua-bot",
      "https://user:pass@api.example.test", "https://api.example.test?q=1"].each do |origin|
      assert_raises(PrismHub::ConfigurationError) do
        PrismHub::Adapters::HttpBotDeliveryGateway.new(
          origin: origin, secret: "secret", path_prefix: "/hua-bot"
        )
      end
    end
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
      chat_id: 123, message_thread_id: 42, created_by_user_identity_id: "user-1", status: "active"
    )
  end
end
