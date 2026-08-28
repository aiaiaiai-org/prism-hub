# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../../test_helper"

class ActorOnboardingEndpointTest < Minitest::Test
  Onboarder = Struct.new(:context, :calls) do
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
    @context = PrismHub::Domain::WorkspaceActorContext.new(
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
    @onboarder = Onboarder.new(@context, [])
    @endpoint = PrismHub::Interfaces::Http::ActorOnboardingEndpoint.new(
      onboard_provider_identity: @onboarder,
      request_body: PrismHub::Interfaces::Http::RequestBody.new
    )
  end

  def test_returns_same_non_enumerating_shape_for_resolved_or_created_actor
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
    refute_includes body.join, "created"
  end

  def test_rejects_mutable_display_metadata_and_non_string_subjects
    invalid_payloads = [
      {"provider" => "telegram", "provider_scope" => "global"},
      {"provider" => "telegram", "provider_scope" => "global", "subject_id" => 123456789},
      {
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
      assert_equal "hub.actor_onboarding.request.invalid", error.code
    end
    assert_empty @onboarder.calls
  end

  private

  def request(payload)
    Rack::Request.new(
      Rack::MockRequest.env_for(
        "/api/v1/actors/onboard",
        method: "POST",
        "CONTENT_TYPE" => "application/json",
        input: JSON.generate(payload)
      )
    )
  end

  def authorisation_context
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-bot",
      capabilities: [PrismHub::Domain::Capabilities::ACTORS_ONBOARD],
      allowed_channel_ids: []
    )
  end
end
