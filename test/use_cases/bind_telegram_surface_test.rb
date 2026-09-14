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
    use_case = PrismHub::UseCases::BindTelegramSurface.new(
      resolve_workspace_actor: resolver,
      binding_repository: repository
    )

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
end
