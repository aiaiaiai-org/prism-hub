# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class BindTelegramSurfaceTest < Minitest::Test
  Actor = Data.define(:user_identity)
  Identity = Data.define(:id)

  class FakeActorResolver
    attr_reader :attributes

    def initialize
      @actor = Actor.new(user_identity: Identity.new(id: "identity-1"))
    end

    def call(**attributes)
      @attributes = attributes
      @actor
    end
  end

  class FakeBindingRepository
    attr_reader :attributes

    def bind(**attributes)
      @attributes = attributes
      PrismHub::Domain::TelegramSurfaceBinding.new(
        id: "binding-1",
        workspace_id: attributes.fetch(:workspace_id),
        bot_instance_id: attributes.fetch(:bot_instance_id),
        logical_channel: attributes.fetch(:logical_channel),
        chat_id: attributes.fetch(:chat_id),
        message_thread_id: attributes.fetch(:message_thread_id),
        created_by_user_identity_id: attributes.fetch(:actor_user_identity_id),
        status: "active"
      )
    end
  end

  def test_resolves_the_human_actor_before_binding
    resolver = FakeActorResolver.new
    repository = FakeBindingRepository.new
    use_case = build(resolver, repository)

    binding = use_case.call(
      authorisation_context: Object.new,
      workspace_id: "workspace-1",
      bot_instance_id: "bot-1",
      logical_channel: "digest",
      chat_id: -1001,
      message_thread_id: 42,
      provider: "telegram",
      provider_scope: "default",
      subject_id: "123"
    )

    assert_equal "binding-1", binding.id
    assert_equal "identity-1", repository.attributes.fetch(:actor_user_identity_id)
    assert_equal "workspace-1", resolver.attributes.fetch(:workspace_id)
    assert_equal "123", resolver.attributes.fetch(:subject_id)
  end

  def test_an_omitted_bot_instance_is_the_callers_own
    repository = FakeBindingRepository.new
    bots = FakeBotInstances.new(PrismHub::Domain::BotInstance.new(
      id: "bot-own", principal_id: "telegram-bot", workspace_id: "workspace-1", status: "active"
    ))
    use_case = build(FakeActorResolver.new, repository, bots)

    use_case.call(**arguments)

    assert_equal "bot-own", repository.attributes.fetch(:bot_instance_id)
    assert_equal({principal_id: "telegram-bot", workspace_id: "workspace-1"}, bots.asked)
  end

  def test_an_explicit_bot_instance_is_used_as_given
    repository = FakeBindingRepository.new
    bots = FakeBotInstances.new(nil)

    build(FakeActorResolver.new, repository, bots).call(**arguments, bot_instance_id: "bot-explicit")

    assert_equal "bot-explicit", repository.attributes.fetch(:bot_instance_id)
    assert_nil bots.asked
  end

  def test_a_caller_without_an_instance_is_told_to_read_the_bot_status_first
    use_case = build(FakeActorResolver.new, FakeBindingRepository.new, FakeBotInstances.new(nil))

    error = assert_raises(PrismHub::TelegramSurfaceBindingConflictError) { use_case.call(**arguments) }

    assert_equal "hub.telegram_surface_binding.bot_instance_unavailable", error.code
  end

  private

  class FakeBotInstances
    attr_reader :asked

    def initialize(instance)
      @instance = instance
    end

    def find(**attributes)
      @asked = attributes
      @instance
    end
  end

  def build(resolver, repository, bots = FakeBotInstances.new(nil))
    PrismHub::UseCases::BindTelegramSurface.new(
      resolve_workspace_actor: resolver,
      binding_repository: repository,
      bot_instance_repository: bots
    )
  end

  def arguments
    {
      authorisation_context: PrismHub::Domain::AuthorisationContext.new(
        principal_id: "telegram-bot", capabilities: [], allowed_channel_ids: []
      ),
      workspace_id: "workspace-1",
      logical_channel: "alerts",
      chat_id: 42,
      message_thread_id: nil,
      provider: "telegram",
      provider_scope: "default",
      subject_id: "123"
    }
  end
end
