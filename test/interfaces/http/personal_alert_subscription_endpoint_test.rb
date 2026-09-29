# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class PersonalAlertSubscriptionEndpointTest < Minitest::Test
  CELL = "860335a97ffffff".freeze
  SUBJECT = {"provider" => "telegram", "provider_scope" => "global", "subject_id" => "123456789"}.freeze
  CHOICE = {"cell" => CELL, "categories" => %w[drone missile], "include_nearby" => false}.freeze

  class Subscriptions
    attr_reader :calls

    def initialize(result:)
      @result = result
      @calls = []
    end

    %i[status save clear].each do |operation|
      define_method(operation) do |**arguments|
        @calls << [operation, arguments]
        @result
      end
    end
  end

  def test_status_returns_only_what_the_person_chose
    subscriptions = Subscriptions.new(result: subscription)

    status, _headers, body = endpoint(subscriptions, :status).call(request(SUBJECT), authorisation_context: context)

    assert_equal 200, status
    assert_equal(
      {"alert_subscription" => {"cell" => CELL, "categories" => %w[drone missile], "include_nearby" => false}},
      JSON.parse(body.join)
    )
    refute_includes body.join, "private-workspace"
    refute_includes body.join, "123456789"
  end

  def test_status_says_null_when_there_is_no_subscription
    _status, _headers, body = endpoint(Subscriptions.new(result: nil), :status)
      .call(request(SUBJECT), authorisation_context: context)

    assert_equal({"alert_subscription" => nil}, JSON.parse(body.join))
  end

  def test_save_passes_the_cell_the_categories_and_the_flag_through
    subscriptions = Subscriptions.new(result: subscription)

    status, _headers, _body = endpoint(subscriptions, :save)
      .call(request(SUBJECT.merge(CHOICE)), authorisation_context: context)

    assert_equal 200, status
    operation, arguments = subscriptions.calls.fetch(0)
    assert_equal :save, operation
    assert_equal CELL, arguments.fetch(:cell)
    assert_equal %w[drone missile], arguments.fetch(:categories)
    assert_equal false, arguments.fetch(:include_nearby)
    assert_equal "123456789", arguments.fetch(:subject_id)
  end

  def test_clear_answers_null
    subscriptions = Subscriptions.new(result: nil)

    status, _headers, body = endpoint(subscriptions, :clear).call(request(SUBJECT), authorisation_context: context)

    assert_equal 200, status
    assert_equal({"alert_subscription" => nil}, JSON.parse(body.join))
    assert_equal :clear, subscriptions.calls.fetch(0).first
  end

  def test_rejects_coordinates_internal_ids_and_missing_or_extra_fields
    invalid = [
      [:status, SUBJECT.merge("cell" => CELL)],
      [:status, SUBJECT.reject { |key, _| key == "subject_id" }],
      [:status, SUBJECT.merge("workspace_id" => "caller-controlled")],
      [:status, SUBJECT.merge("subject_id" => 123)],
      [:clear, SUBJECT.merge("categories" => ["drone"])],
      [:save, SUBJECT.merge(CHOICE).merge("lat" => 50.45, "lon" => 30.52)],
      [:save, SUBJECT.merge(CHOICE).reject { |key, _| key == "cell" }],
      [:save, SUBJECT]
    ]

    invalid.each do |operation, payload|
      subscriptions = Subscriptions.new(result: nil)
      error = assert_raises(PrismHub::InputError, "#{operation} #{payload.keys}") do
        endpoint(subscriptions, operation).call(request(payload), authorisation_context: context)
      end
      assert_equal "hub.alert_subscription.request.invalid", error.code
      assert_empty subscriptions.calls
    end
  end

  def test_an_unknown_operation_is_a_programming_error
    assert_raises(ArgumentError) { endpoint(Subscriptions.new(result: nil), :delete) }
  end

  private

  def endpoint(subscriptions, operation)
    PrismHub::Interfaces::Http::PersonalAlertSubscriptionEndpoint.new(
      subscription: subscriptions,
      operation: operation,
      request_body: PrismHub::Interfaces::Http::RequestBody.new
    )
  end

  def subscription
    PrismHub::Domain::AlertSubscription.new(
      workspace_id: "private-workspace",
      cell: CELL,
      categories: %w[drone missile],
      include_nearby: false,
      updated_at: Time.utc(2026, 9, 30, 9, 0)
    )
  end

  def request(payload)
    Rack::Request.new(
      Rack::MockRequest.env_for(
        "/api/v1/alert-subscriptions/personal/status",
        method: "POST",
        "CONTENT_TYPE" => "application/json",
        input: JSON.generate(payload)
      )
    )
  end

  def context
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-client",
      capabilities: [PrismHub::Domain::Capabilities::ALERT_SUBSCRIPTIONS_READ],
      allowed_channel_ids: []
    )
  end
end
