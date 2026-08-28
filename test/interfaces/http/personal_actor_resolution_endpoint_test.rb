# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class PersonalActorResolutionEndpointTest < Minitest::Test
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
    context = PrismHub::Domain::WorkspaceActorContext.new(
      principal_id: "telegram-bot",
      workspace_id: "personal-1",
      user_identity: identity,
      role: "owner",
      provider_subject: PrismHub::Domain::ProviderSubject.new(
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      )
    )
    @resolver = Resolver.new(context, [])
    @endpoint = PrismHub::Interfaces::Http::PersonalActorResolutionEndpoint.new(
      resolve_personal_actor: @resolver,
      request_body: PrismHub::Interfaces::Http::RequestBody.new
    )
  end

  def test_returns_only_canonical_identity_personal_workspace_and_owner_role
    status, _headers, body = @endpoint.call(
      request(
        "provider" => "telegram",
        "provider_scope" => "global",
        "subject_id" => "123456789"
      ),
      authorisation_context: authorisation_context
    )

    assert_equal 200, status
    assert_equal(
      {
        "actor" => {
          "identity" => {"type" => "person", "id" => "0x0sky"},
          "workspace_id" => "personal-1",
          "role" => "owner"
        }
      },
      JSON.parse(body.join)
    )
    refute_includes body.join, "123456789"
  end

  def test_rejects_extra_or_non_string_fields_before_resolution
    invalid_payloads = [
      {"provider" => "telegram", "provider_scope" => "global"},
      {"provider" => "telegram", "provider_scope" => "global", "subject_id" => 123456789},
      {
        "provider" => "telegram",
        "provider_scope" => "global",
        "subject_id" => "123456789",
        "workspace_id" => "caller-controlled"
      }
    ]

    invalid_payloads.each do |payload|
      error = assert_raises(PrismHub::InputError) do
        @endpoint.call(request(payload), authorisation_context: authorisation_context)
      end
      assert_equal "hub.personal_actor.request.invalid", error.code
    end
    assert_empty @resolver.calls
  end

  private

  def request(payload)
    Rack::Request.new(
      Rack::MockRequest.env_for(
        "/api/v1/actors/personal/resolve",
        method: "POST",
        "CONTENT_TYPE" => "application/json",
        input: JSON.generate(payload)
      )
    )
  end

  def authorisation_context
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-bot",
      capabilities: [PrismHub::Domain::Capabilities::ACTORS_RESOLVE],
      allowed_channel_ids: []
    )
  end
end
