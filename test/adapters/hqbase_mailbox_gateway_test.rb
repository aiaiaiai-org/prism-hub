# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class HqbaseMailboxGatewayTest < Minitest::Test
  def test_lists_mailboxes_and_ignores_additive_fields
    requests = []
    transport = lambda do |uri:, headers:|
      requests << {uri: uri, headers: headers}
      {
        status: 200,
        body: JSON.generate([
          {
            "id" => "mbx_prism",
            "address" => "prism@aiaiaiai.org",
            "displayName" => "Prism",
            "isActive" => true,
            "accessLevel" => "manager",
            "futureField" => {"ignored" => true}
          }
        ])
      }
    end

    gateway = PrismHub::Adapters::HqbaseMailboxGateway.new(
      origin: "https://mail.aiaiaiai.org",
      transport: transport
    )
    mailboxes = gateway.list(access_token: "secret-token")

    assert_equal 1, mailboxes.length
    assert_equal(
      {
        "id" => "mbx_prism",
        "address" => "prism@aiaiaiai.org",
        "display_name" => "Prism",
        "is_active" => true,
        "access_level" => "manager"
      },
      mailboxes.fetch(0).public_attributes
    )
    request = requests.fetch(0)
    assert_equal "/api/v1/mailboxes", request.fetch(:uri).request_uri
    assert_equal "Bearer secret-token", request.fetch(:headers).fetch("authorization")
  end

  def test_maps_authorisation_failure_to_typed_error
    gateway = PrismHub::Adapters::HqbaseMailboxGateway.new(
      origin: "https://mail.aiaiaiai.org",
      transport: ->(**) { {status: 403, body: '{"error":"forbidden"}'} }
    )

    error = assert_raises(PrismHub::AuthorisationError) do
      gateway.list(access_token: "secret-token")
    end

    assert_equal "hub.mail.mailboxes.access_denied", error.code
  end

  def test_rejects_invalid_mailbox_payload
    gateway = PrismHub::Adapters::HqbaseMailboxGateway.new(
      origin: "https://mail.aiaiaiai.org",
      transport: ->(**) { {status: 200, body: '[{"id":"mbx_1"}]'} }
    )

    error = assert_raises(PrismHub::ExecutionUnavailableError) do
      gateway.list(access_token: "secret-token")
    end

    assert_equal "hub.mail.mailboxes.invalid_json", error.code
  end
end
