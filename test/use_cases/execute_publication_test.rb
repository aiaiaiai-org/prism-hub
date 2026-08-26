# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ExecutePublicationTest < Minitest::Test
  def test_maps_public_channel_to_prism_binding
    gateway = PrismHubTestSupport::FakeExecutionGateway.new
    use_case = build_use_case(gateway)
    draft = PrismHub::Domain::PublicationDraft.from_hash(
      PrismHubTestSupport.publication_hash
    )

    use_case.call(
      draft: draft,
      idempotency_key: "telegram:42:100",
      request_id: "request-test-1"
    )

    envelope = gateway.envelopes.fetch(0)
    target = envelope.dig("payload", "targets", 0)
    assert_equal "publish", envelope.fetch("operation")
    assert_equal "meta.threads", target.fetch("provider_id")
    assert_equal "0x0sky", target.fetch("channel")
    assert_equal "threads.personal", target.fetch("credential")
    refute target.key?("channel_id")
  end

  def test_rejects_an_unknown_channel_before_execution
    gateway = PrismHubTestSupport::FakeExecutionGateway.new
    value = PrismHubTestSupport.publication_hash
    value.fetch("targets").first["channel_id"] = "missing"
    draft = PrismHub::Domain::PublicationDraft.from_hash(value)

    error = assert_raises(PrismHub::UnknownChannelError) do
      build_use_case(gateway).call(
        draft: draft,
        idempotency_key: "key-1",
        request_id: "request-test-1"
      )
    end

    assert_equal "hub.channel.not_found", error.code
    assert_empty gateway.envelopes
  end

  private

  def build_use_case(gateway)
    PrismHub::UseCases::ExecutePublication.new(
      operation: "publish",
      channel_repository: PrismHubTestSupport.channels,
      execution_gateway: gateway
    )
  end
end
