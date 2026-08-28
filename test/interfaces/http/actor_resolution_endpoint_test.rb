# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class ActorResolutionEndpointTest < Minitest::Test
  Resolver = Struct.new(:context, :calls) do
    def call(**arguments)
      calls << arguments
      context
    end
  end

  def setup
    identity = PrismHub::Domain::UserIdentity.new(
      id: "identity-1",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0x0sky"),
      status: "active"
    )
    provider_subject = PrismHub::Domain::ProviderSubject.new(
      provider: "telegram",
      provider_scope: "global",
      subject_id: "123456789"
    )
    @context = PrismHub::Domain::WorkspaceActorContext.new(
      principal_id: "bot-personal",
      workspace_id: "personal",
      user_identity: identity,
      role: "owner",
      provider_subject: provider_subject
    )
    @resolver = Resolver.new(@context, [])
    @endpoint = PrismHub::Interfaces::Http::ActorResolutionEndpoint.new(
      resolve_workspace_actor: @resolver,
      request_body: PrismHub::Interfaces::Http::RequestBody.new
    )
  end

  def test_returns_only_canonical_identity_and_workspace_role
    status, _headers, body = @endpoint.call(
      request(
        {
          "workspace_id" => "personal",
          "provider" => "telegram",
          "provider_scope" => "global",
          "subject_id" => "123456789"
        }
      ),
      authorisation_context: authorisation_context
    )

    payload = JSON.parse(body.join)
    assert_equal 200, status
    assert_equal(
      {"actor" => {"identity" => {"type" => "person", "id" => "0x0sky"}, "role" => "owner"}},
      payload
    )
    refute_includes body.join, "123456789"
    assert_equal "123456789", @resolver.calls.first.fetch(:subject_id)
    assert_equal "personal", @resolver.calls.first.fetch(:workspace_id)
  end

  def test_rejects_missing_extra_or_non_string_fields_before_resolution
    invalid_payloads = [
      {"workspace_id" => "personal", "provider" => "telegram", "provider_scope" => "global"},
      {
        "workspace_id" => "personal",
        "provider" => "telegram",
        "provider_scope" => "global",
        "subject_id" => 123456789
      },
      {
        "workspace_id" => "personal",
        "provider" => "telegram",
        "provider_scope" => "global",
        "subject_id" => "123456789",
        "username" => "mutable-handle"
      }
    ]

    invalid_payloads.each do |payload|
      error = assert_raises(PrismHub::InputError) do
        @endpoint.call(request(payload), authorisation_context: authorisation_context)
      end
      assert_equal "hub.actor.request.invalid", error.code
    end
    assert_empty @resolver.calls
  end

  private

  def request(payload)
    Rack::Request.new(
      Rack::MockRequest.env_for(
        "/api/v1/actors/resolve",
        method: "POST",
        "CONTENT_TYPE" => "application/json",
        input: JSON.generate(payload)
      )
    )
  end

  def authorisation_context
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "bot-personal",
      capabilities: [PrismHub::Domain::Capabilities::ACTORS_RESOLVE],
      allowed_channel_ids: []
    )
  end
end
