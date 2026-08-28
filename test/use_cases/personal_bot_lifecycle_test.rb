# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class PersonalBotLifecycleTest < Minitest::Test
  class FakeResolver
    attr_reader :calls

    def initialize(actor)
      @actor = actor
      @calls = []
    end

    def call(**arguments)
      @calls << arguments
      @actor
    end
  end

  class FakeRepository
    attr_reader :calls

    def initialize(error: nil)
      @error = error
      @calls = []
    end

    %i[ensure pause resume].each do |operation|
      define_method(operation) do |**arguments|
        @calls << [operation, arguments]
        raise @error if @error

        PrismHub::Domain::BotInstance.new(
          id: "instance-1",
          principal_id: arguments.fetch(:principal_id),
          workspace_id: arguments.fetch(:workspace_id),
          status: operation == :pause ? "paused" : "active",
          paused_at: operation == :pause ? arguments.fetch(:occurred_at) : nil
        )
      end
    end
  end

  def setup
    @actor = actor_context
    @resolver = FakeResolver.new(@actor)
    @repository = FakeRepository.new
    @clock = -> { Time.utc(2026, 8, 28, 4, 20) }
  end

  def test_status_requires_lifecycle_read_before_actor_lookup
    lifecycle = lifecycle_with(@repository)

    error = assert_raises(PrismHub::AuthorisationError) do
      lifecycle.status(
        authorisation_context: authorisation_context([]),
        **provider_evidence
      )
    end

    assert_equal "hub.authorization.capability_denied", error.code
    assert_empty @resolver.calls
    assert_empty @repository.calls
  end

  def test_pause_uses_server_derived_principal_workspace_and_actor
    lifecycle = lifecycle_with(@repository)

    instance = lifecycle.pause(
      authorisation_context: authorisation_context([PrismHub::Domain::Capabilities::BOT_INSTANCES_MANAGE]),
      **provider_evidence
    )

    assert instance.paused?
    operation, arguments = @repository.calls.fetch(0)
    assert_equal :pause, operation
    assert_equal "telegram-client", arguments.fetch(:principal_id)
    assert_equal "personal-user", arguments.fetch(:workspace_id)
    assert_equal @actor.user_identity.id, arguments.fetch(:actor_user_identity_id)
    assert_equal @clock.call, arguments.fetch(:occurred_at)
  end

  def test_owner_race_is_collapsed_to_actor_not_authorized
    repository = FakeRepository.new(
      error: PrismHub::BotInstanceConflictError.new(
        "hub.bot_instance.owner_required",
        "private ownership detail"
      )
    )
    lifecycle = lifecycle_with(repository)

    error = assert_raises(PrismHub::AuthorisationError) do
      lifecycle.resume(
        authorisation_context: authorisation_context([PrismHub::Domain::Capabilities::BOT_INSTANCES_MANAGE]),
        **provider_evidence
      )
    end

    assert_equal "hub.actor.not_authorized", error.code
    refute_includes error.message, "private ownership detail"
  end

  def test_disabled_state_remains_a_typed_conflict
    repository = FakeRepository.new(
      error: PrismHub::BotInstanceConflictError.new(
        "hub.bot_instance.disabled",
        "administrative recovery required"
      )
    )
    lifecycle = lifecycle_with(repository)

    error = assert_raises(PrismHub::BotInstanceConflictError) do
      lifecycle.resume(
        authorisation_context: authorisation_context([PrismHub::Domain::Capabilities::BOT_INSTANCES_MANAGE]),
        **provider_evidence
      )
    end

    assert_equal "hub.bot_instance.disabled", error.code
  end

  private

  def lifecycle_with(repository)
    PrismHub::UseCases::PersonalBotLifecycle.new(
      resolve_personal_actor: @resolver,
      bot_instance_repository: repository,
      clock: @clock
    )
  end

  def authorisation_context(capabilities)
    PrismHub::Domain::AuthorisationContext.new(
      principal_id: "telegram-client",
      capabilities: capabilities,
      allowed_channel_ids: []
    )
  end

  def provider_evidence
    {provider: "telegram", provider_scope: "global", subject_id: "123456789"}
  end

  def actor_context
    identity = PrismHub::Domain::UserIdentity.new(
      id: "user-identity-1",
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: "0xuser"),
      status: "active"
    )
    PrismHub::Domain::WorkspaceActorContext.new(
      principal_id: "telegram-client",
      workspace_id: "personal-user",
      user_identity: identity,
      role: "owner",
      provider_subject: PrismHub::Domain::ProviderSubject.new(
        provider: "telegram",
        provider_scope: "global",
        subject_id: "123456789"
      )
    )
  end
end
