# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../../config/environment"
require_relative "../../test_helper"

# The whole path a Telegram client takes, through the real composition and a real database:
# credential, onboarding, subscription, and the errors a client must be able to tell apart.
class AlertSubscriptionFlowTest < Minitest::Test
  CELL = "860335a97ffffff".freeze
  SUBJECT = {"provider" => "telegram", "provider_scope" => "global", "subject_id" => "424242"}.freeze
  CAPABILITIES = [
    PrismHub::Domain::Capabilities::ACTORS_ONBOARD,
    PrismHub::Domain::Capabilities::ACTORS_RESOLVE,
    PrismHub::Domain::Capabilities::ALERT_SUBSCRIPTIONS_READ,
    PrismHub::Domain::Capabilities::ALERT_SUBSCRIPTIONS_MANAGE
  ].freeze

  def setup
    clear_tables
    @logger = Logger.new(StringIO.new)
    @app = PrismHub::Bootstrap.build(env: {}, logger: @logger)
    @token = credential("telegram-client", CAPABILITIES)
    post("/api/v1/actors/onboard", SUBJECT, @token)
  end

  def teardown
    clear_tables
  end

  def test_a_person_sets_reads_changes_and_clears_a_subscription
    assert_equal({"alert_subscription" => nil}, body(post(path("status"), SUBJECT, @token)))

    saved = post(path("save"), SUBJECT.merge(choice), @token)
    assert_equal 200, saved.status
    assert_equal({"cell" => CELL, "categories" => %w[drone missile], "include_nearby" => false},
      body(saved).fetch("alert_subscription"))
    assert_equal body(saved), body(post(path("status"), SUBJECT, @token))

    changed = post(path("save"), SUBJECT.merge(choice("categories" => %w[bomb], "include_nearby" => true)), @token)
    assert_equal %w[bomb], body(changed).dig("alert_subscription", "categories")
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::AlertSubscription.count

    cleared = post(path("clear"), SUBJECT, @token)
    assert_equal 200, cleared.status
    assert_equal({"alert_subscription" => nil}, body(cleared))
    assert_equal({"alert_subscription" => nil}, body(post(path("status"), SUBJECT, @token)))
    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::AlertSubscription.count
  end

  def test_no_credential_is_401_and_a_missing_capability_is_403
    assert_equal 401, post(path("status"), SUBJECT, nil).status
    assert_equal 401, post(path("save"), SUBJECT.merge(choice), "prism_client_v1_#{"x" * 43}").status

    read_only = credential("read-only", [PrismHub::Domain::Capabilities::ACTORS_RESOLVE,
      PrismHub::Domain::Capabilities::ALERT_SUBSCRIPTIONS_READ])
    assert_equal 200, post(path("status"), SUBJECT, read_only).status
    denied = post(path("save"), SUBJECT.merge(choice), read_only)
    assert_equal 403, denied.status
    assert_equal "hub.authorization.capability_denied", body(denied).dig("error", "code")
    assert_equal 403, post(path("clear"), SUBJECT, read_only).status
  end

  def test_a_person_the_hub_does_not_know_is_403_and_nothing_is_stored
    stranger = SUBJECT.merge("subject_id" => "999999")

    response = post(path("save"), stranger.merge(choice), @token)

    assert_equal 403, response.status
    assert_equal "hub.actor.not_authorized", body(response).dig("error", "code")
    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::AlertSubscription.count
  end

  def test_a_bad_request_is_400_and_a_bad_value_is_422
    assert_equal 400, post(path("save"), SUBJECT.merge(choice).merge("lat" => 50.45, "lon" => 30.52), @token).status
    assert_equal 400, post(path("save"), SUBJECT, @token).status
    assert_equal 400, post(path("status"), SUBJECT.merge("cell" => CELL), @token).status

    coordinates = post(path("save"), SUBJECT.merge(choice("cell" => "50.4501,30.5234")), @token)
    assert_equal 422, coordinates.status
    assert_equal "hub.alert_subscription.cell.invalid", body(coordinates).dig("error", "code")
    assert_equal 422, post(path("save"), SUBJECT.merge(choice("categories" => [])), @token).status
    assert_equal 422, post(path("save"), SUBJECT.merge(choice("categories" => %w[shahed])), @token).status
    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::AlertSubscription.count
  end

  def test_the_only_method_is_post
    response = call("GET", path("status"), nil, @token)
    assert_equal 405, response.status
  end

  def test_one_person_cannot_reach_another_persons_subscription
    post(path("save"), SUBJECT.merge(choice), @token)
    other = SUBJECT.merge("subject_id" => "515151")
    post("/api/v1/actors/onboard", other, @token)

    assert_equal({"alert_subscription" => nil}, body(post(path("status"), other, @token)))
    post(path("clear"), other, @token)
    assert_equal CELL, body(post(path("status"), SUBJECT, @token)).dig("alert_subscription", "cell")
  end

  private

  def path(operation)
    "/api/v1/alert-subscriptions/personal/#{operation}"
  end

  def choice(overrides = {})
    {"cell" => CELL, "categories" => %w[missile drone], "include_nearby" => false}.merge(overrides)
  end

  def post(path, payload, token)
    call("POST", path, payload, token)
  end

  def call(method, path, payload, token)
    headers = {method: method, "CONTENT_TYPE" => "application/json"}
    headers[:input] = JSON.generate(payload) if payload
    headers["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    status, response_headers, response_body = @app.call(Rack::MockRequest.env_for(path, headers))
    Rack::MockResponse.new(status, response_headers, response_body)
  end

  def body(response)
    JSON.parse(response.body)
  end

  def credential(principal_id, capabilities)
    PrismHub::UseCases::ProvisionServicePrincipal
      .new(repository: PrismHub::Adapters::ActiveRecordServicePrincipalRepository.new)
      .call(principal_id: principal_id, capabilities: capabilities, channel_ids: [])
    PrismHub::UseCases::IssueClientCredential.new(
      repository: PrismHub::Adapters::ActiveRecordClientCredentialRepository.new,
      token_generator: PrismHub::Adapters::SecureClientCredentialGenerator.new
    ).call(principal_id: principal_id).token
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
      alert_subscriptions
      bot_instance_lifecycle_events
      bot_instances
      workspace_memberships
      provider_identity_bindings
      client_credentials
      capability_grants
      channel_grants
      service_principals
      user_identities
      workspaces
    ].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
