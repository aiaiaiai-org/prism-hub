# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class TelegramSurfaceBindingEndpointTest < Minitest::Test
  BODY = {
    "workspace_id" => "personal-a", "logical_channel" => "alerts", "chat_id" => 42,
    "provider" => "telegram", "provider_scope" => "h-ua-bot", "subject_id" => "42"
  }.freeze

  class Binder
    attr_reader :arguments

    def call(**arguments)
      @arguments = arguments
      PrismHub::Domain::TelegramSurfaceBinding.new(
        id: "binding-1", workspace_id: arguments.fetch(:workspace_id), bot_instance_id: "bot-own",
        logical_channel: arguments.fetch(:logical_channel), chat_id: arguments.fetch(:chat_id),
        message_thread_id: arguments[:message_thread_id], created_by_user_identity_id: "identity-1",
        status: "active"
      )
    end
  end

  def test_binds_without_an_instance_and_returns_the_binding
    binder = Binder.new

    status, _headers, body = call(BODY, binder)

    assert_equal 200, status
    assert_nil binder.arguments.fetch(:bot_instance_id)
    assert_equal(
      {"id" => "binding-1", "workspace_id" => "personal-a", "bot_instance_id" => "bot-own",
       "logical_channel" => "alerts", "chat_id" => 42, "message_thread_id" => nil, "status" => "active"},
      JSON.parse(body.join).fetch("binding")
    )
  end

  def test_an_explicit_instance_and_thread_are_passed_through
    binder = Binder.new

    call(BODY.merge("bot_instance_id" => "bot-x", "message_thread_id" => 7), binder)

    assert_equal "bot-x", binder.arguments.fetch(:bot_instance_id)
    assert_equal 7, binder.arguments.fetch(:message_thread_id)
  end

  def test_rejects_missing_extra_and_mistyped_fields
    invalid = [
      BODY.reject { |key, _| key == "chat_id" },
      BODY.merge("lat" => 50.4),
      BODY.merge("chat_id" => "42"),
      BODY.merge("bot_instance_id" => ""),
      BODY.merge("message_thread_id" => 0),
      BODY.merge("subject_id" => 42)
    ]

    invalid.each do |payload|
      binder = Binder.new
      error = assert_raises(PrismHub::InputError, payload.inspect) { call(payload, binder) }
      assert_equal "hub.telegram_surface_binding.request.invalid", error.code
      assert_nil binder.arguments
    end
  end

  private

  def call(payload, binder)
    endpoint = PrismHub::Interfaces::Http::TelegramSurfaceBindingEndpoint.new(
      bind_telegram_surface: binder,
      request_body: PrismHub::Interfaces::Http::RequestBody.new
    )
    request = Rack::Request.new(Rack::MockRequest.env_for(
      "/api/v1/telegram/surfaces/bind", method: "POST", input: JSON.generate(payload),
      "CONTENT_TYPE" => "application/json"
    ))
    endpoint.call(request, authorisation_context: PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-bot", capabilities: [], allowed_channel_ids: []
    ))
  end
end
