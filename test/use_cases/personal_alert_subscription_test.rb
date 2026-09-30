# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class PersonalAlertSubscriptionTest < Minitest::Test
  CELL = "860335a97ffffff".freeze
  READ = PrismHub::Domain::Capabilities::ALERT_SUBSCRIPTIONS_READ
  MANAGE = PrismHub::Domain::Capabilities::ALERT_SUBSCRIPTIONS_MANAGE

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

    def initialize(stored: nil, error: nil)
      @stored = stored
      @error = error
      @calls = []
    end

    def find(**arguments)
      @calls << [:find, arguments]
      @stored
    end

    def save(**arguments)
      @calls << [:save, arguments]
      raise @error if @error

      PrismHub::Domain::AlertSubscription.new(
        workspace_id: arguments.fetch(:workspace_id),
        cell: arguments.fetch(:cell),
        categories: arguments.fetch(:categories),
        include_nearby: arguments.fetch(:include_nearby),
        updated_at: arguments.fetch(:occurred_at)
      )
    end

    def clear(**arguments)
      @calls << [:clear, arguments]
      raise @error if @error

      nil
    end
  end

  def setup
    @resolver = FakeResolver.new(actor_context)
    @repository = FakeRepository.new
    @clock = -> { Time.utc(2026, 9, 30, 9, 0) }
  end

  def test_status_needs_the_read_capability_before_any_lookup
    error = assert_raises(PrismHub::AuthorisationError) do
      use_case.status(authorisation_context: context([MANAGE]), **provider_evidence)
    end

    assert_equal "hub.authorization.capability_denied", error.code
    assert_empty @resolver.calls
    assert_empty @repository.calls
  end

  def test_status_reads_the_subscription_of_the_server_resolved_workspace
    stored = subscription
    repository = FakeRepository.new(stored: stored)

    found = use_case(repository: repository).status(authorisation_context: context([READ]), **provider_evidence)

    assert_same stored, found
    assert_equal [[:find, {workspace_id: "personal-user"}]], repository.calls
  end

  def test_status_is_nil_when_the_person_has_no_subscription
    assert_nil use_case.status(authorisation_context: context([READ]), **provider_evidence)
  end

  def test_save_needs_the_manage_capability
    error = assert_raises(PrismHub::AuthorisationError) do
      use_case.save(authorisation_context: context([READ]), **provider_evidence, **choice)
    end

    assert_equal "hub.authorization.capability_denied", error.code
    assert_empty @repository.calls
  end

  def test_save_uses_the_server_derived_workspace_and_actor_never_the_callers
    saved = use_case.save(authorisation_context: context([MANAGE]), **provider_evidence, **choice)

    assert_equal CELL, saved.cell
    operation, arguments = @repository.calls.fetch(0)
    assert_equal :save, operation
    assert_equal "personal-user", arguments.fetch(:workspace_id)
    assert_equal "user-identity-1", arguments.fetch(:actor_user_identity_id)
    assert_equal %w[drone missile], arguments.fetch(:categories)
    assert_equal @clock.call, arguments.fetch(:occurred_at)
  end

  def test_an_invalid_choice_is_refused_before_anything_is_stored
    [
      choice(cell: "50.4501,30.5234"),
      choice(categories: []),
      choice(include_nearby: "yes")
    ].each do |bad|
      assert_raises(PrismHub::InputError) do
        use_case.save(authorisation_context: context([MANAGE]), **provider_evidence, **bad)
      end
    end
    assert_empty @repository.calls
  end

  def test_clear_deletes_through_the_repository_and_returns_nothing
    assert_nil use_case.clear(authorisation_context: context([MANAGE]), **provider_evidence)

    operation, arguments = @repository.calls.fetch(0)
    assert_equal :clear, operation
    assert_equal "personal-user", arguments.fetch(:workspace_id)
  end

  def test_clear_needs_the_manage_capability
    assert_raises(PrismHub::AuthorisationError) do
      use_case.clear(authorisation_context: context([READ]), **provider_evidence)
    end
    assert_empty @repository.calls
  end

  def test_an_owner_race_is_collapsed_to_actor_not_authorized
    error_from_repository = PrismHub::AlertSubscriptionConflictError.new(
      "hub.alert_subscription.owner_required",
      "private ownership detail"
    )
    repository = FakeRepository.new(error: error_from_repository)

    save_error = assert_raises(PrismHub::AuthorisationError) do
      use_case(repository: repository).save(authorisation_context: context([MANAGE]), **provider_evidence, **choice)
    end
    clear_error = assert_raises(PrismHub::AuthorisationError) do
      use_case(repository: repository).clear(authorisation_context: context([MANAGE]), **provider_evidence)
    end

    [save_error, clear_error].each do |error|
      assert_equal "hub.actor.not_authorized", error.code
      refute_includes error.message, "private ownership detail"
    end
  end

  def test_other_conflicts_are_not_hidden
    repository = FakeRepository.new(
      error: PrismHub::AlertSubscriptionConflictError.new("hub.alert_subscription.workspace_unavailable", "unavailable")
    )

    error = assert_raises(PrismHub::AlertSubscriptionConflictError) do
      use_case(repository: repository).clear(authorisation_context: context([MANAGE]), **provider_evidence)
    end
    assert_equal "hub.alert_subscription.workspace_unavailable", error.code
  end

  def test_a_context_that_is_not_an_authorisation_context_is_a_programming_error
    assert_raises(ArgumentError) do
      use_case.status(authorisation_context: Object.new, **provider_evidence)
    end
  end

  private

  def use_case(repository: @repository)
    PrismHub::UseCases::PersonalAlertSubscription.new(
      resolve_personal_actor: @resolver,
      alert_subscription_repository: repository,
      clock: @clock
    )
  end

  def choice(**overrides)
    {cell: CELL, categories: %w[missile drone], include_nearby: true}.merge(overrides)
  end

  def subscription
    PrismHub::Domain::AlertSubscription.new(
      workspace_id: "personal-user",
      cell: CELL,
      categories: %w[drone],
      include_nearby: false,
      updated_at: @clock.call
    )
  end

  def context(capabilities)
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
