# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ExecutePublicationTest < Minitest::Test
  def test_maps_an_authorised_public_channel_to_prism_binding
    gateway = PrismHubTestSupport::FakeExecutionGateway.new
    use_case = build_use_case(gateway)
    draft = PrismHub::Domain::PublicationDraft.from_hash(
      PrismHubTestSupport.publication_hash
    )

    use_case.call(
      draft: draft,
      idempotency_key: "telegram:42:100",
      request_id: "request-test-1",
      authorisation_context: publish_context(channels: ["personal-threads"])
    )

    envelope = gateway.envelopes.fetch(0)
    target = envelope.dig("payload", "targets", 0)
    assert_equal "publish", envelope.fetch("operation")
    assert_equal "meta.threads", target.fetch("provider_id")
    assert_equal "0x0sky", target.fetch("channel")
    assert_equal "threads.personal", target.fetch("credential")
    refute target.key?("channel_id")
  end

  def test_rejects_a_target_outside_principal_scope_before_channel_lookup_or_execution
    gateway = PrismHubTestSupport::FakeExecutionGateway.new
    value = PrismHubTestSupport.publication_hash
    value.fetch("targets").first["channel_id"] = "missing"
    draft = PrismHub::Domain::PublicationDraft.from_hash(value)

    error = assert_raises(PrismHub::AuthorisationError) do
      build_use_case(gateway).call(
        draft: draft,
        idempotency_key: "key-1",
        request_id: "request-test-1",
        authorisation_context: publish_context(channels: ["personal-threads"])
      )
    end

    assert_equal "hub.authorization.channel_denied", error.code
    assert_equal ["missing"], error.details.fetch("channel_ids")
    assert_empty gateway.envelopes
  end

  def test_requires_operation_capability_before_execution
    gateway = PrismHubTestSupport::FakeExecutionGateway.new
    draft = PrismHub::Domain::PublicationDraft.from_hash(
      PrismHubTestSupport.publication_hash
    )

    error = assert_raises(PrismHub::AuthorisationError) do
      build_use_case(gateway).call(
        draft: draft,
        idempotency_key: "key-1",
        request_id: "request-test-1",
        authorisation_context: PrismHub::Domain::AuthorisationContext.new(
          principal_id: "telegram-personal",
          capabilities: [PrismHub::Domain::Capabilities::PUBLICATIONS_VALIDATE],
          allowed_channel_ids: ["personal-threads"]
        )
      )
    end

    assert_equal "hub.authorization.capability_denied", error.code
    assert_empty gateway.envelopes
  end

  private

  def publish_context(channels:)
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-personal",
      capabilities: [PrismHub::Domain::Capabilities::PUBLICATIONS_PUBLISH],
      allowed_channel_ids: channels
    )
  end

  def build_use_case(gateway)
    PrismHub::UseCases::ExecutePublication.new(
      operation: "publish",
      channel_repository: PrismHubTestSupport.channels,
      execution_gateway: gateway
    )
  end
end
