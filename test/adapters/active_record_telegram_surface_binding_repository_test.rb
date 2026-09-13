# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordTelegramSurfaceBindingRepositoryTest < Minitest::Test
  def setup
    clear_tables
    @identity_repository = PrismHub::Adapters::ActiveRecordUserIdentityRepository.new
    @membership_repository = PrismHub::Adapters::ActiveRecordWorkspaceMembershipRepository.new
    @bot_repository = PrismHub::Adapters::ActiveRecordBotInstanceRepository.new
    @repository = PrismHub::Adapters::ActiveRecordTelegramSurfaceBindingRepository.new

    @principal = PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal.create!(
      identifier: "telegram-bot",
      status: "active"
    )
    @workspace = PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(
      identifier: "personal-a",
      status: "active"
    )
    @owner = provision_identity("0xowner")
    @member = provision_identity("0xmember")
    @membership_repository.grant(
      user_identity: @owner,
      workspace_id: @workspace.identifier,
      role: "owner"
    )
    @membership_repository.grant(
      user_identity: @member,
      workspace_id: @workspace.identifier,
      role: "member"
    )
    @bot = @bot_repository.ensure(
      principal_id: @principal.identifier,
      workspace_id: @workspace.identifier,
      actor_user_identity_id: @owner.id,
      occurred_at: Time.utc(2026, 9, 13, 8, 0)
    )
  end

  def teardown
    clear_tables
  end

  def test_bind_is_idempotent_for_the_same_logical_and_physical_surface
    first = bind
    second = bind

    assert_equal first.id, second.id
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::TelegramSurfaceBinding.count
    assert_equal "digest", second.logical_channel
    assert_equal(-1001234567890, second.chat_id)
  end

  def test_one_active_logical_context_cannot_point_to_two_surfaces
    bind

    error = assert_raises(PrismHub::TelegramSurfaceBindingConflictError) do
      bind(chat_id: -1001234567891, message_thread_id: 99)
    end

    assert_equal "hub.telegram_surface_binding.logical_context_taken", error.code
  end

  def test_one_active_surface_cannot_serve_two_logical_channels
    bind(message_thread_id: 42)

    error = assert_raises(PrismHub::TelegramSurfaceBindingConflictError) do
      bind(logical_channel: "alerts", message_thread_id: 42)
    end

    assert_equal "hub.telegram_surface_binding.surface_taken", error.code
  end

  def test_root_and_topics_in_the_same_chat_are_independent_surfaces
    root = bind(logical_channel: "root")
    first_topic = bind(logical_channel: "digest", message_thread_id: 42)
    second_topic = bind(logical_channel: "alerts", message_thread_id: 43)

    refute_equal root.id, first_topic.id
    refute_equal first_topic.id, second_topic.id
    assert_equal "telegram:-1001234567890:root", root.surface_scope
    assert_equal "telegram:-1001234567890:42", first_topic.surface_scope
    assert_equal "telegram:-1001234567890:43", second_topic.surface_scope
  end

  def test_find_resolves_only_active_bindings_from_either_direction
    binding = bind(message_thread_id: 42)

    by_context = @repository.find_by_logical_context(
      workspace_id: @workspace.identifier,
      logical_channel: "digest"
    )
    by_surface = @repository.find_by_surface(
      bot_instance_id: @bot.id,
      chat_id: -1001234567890,
      message_thread_id: 42
    )

    assert_equal binding.id, by_context.id
    assert_equal binding.id, by_surface.id

    @repository.revoke(
      id: binding.id,
      actor_user_identity_id: @owner.id,
      revoked_at: Time.utc(2026, 9, 13, 8, 5)
    )

    assert_nil @repository.find_by_logical_context(
      workspace_id: @workspace.identifier,
      logical_channel: "digest"
    )
    assert_nil @repository.find_by_surface(
      bot_instance_id: @bot.id,
      chat_id: -1001234567890,
      message_thread_id: 42
    )
  end

  def test_revocation_is_audited_and_frees_both_active_uniqueness_constraints
    first = bind(message_thread_id: 42)
    revoked_at = Time.utc(2026, 9, 13, 8, 6)

    revoked = @repository.revoke(
      id: first.id,
      actor_user_identity_id: @owner.id,
      revoked_at: revoked_at
    )
    replacement = bind(message_thread_id: 42)

    assert_predicate revoked, :revoked?
    assert_equal revoked_at, revoked.revoked_at
    assert_equal @owner.id, revoked.revoked_by_user_identity_id
    assert_equal @owner.id, revoked.created_by_user_identity_id
    refute_equal first.id, replacement.id
    assert_equal 2, PrismHub::Adapters::ActiveRecordRecords::TelegramSurfaceBinding.count
  end

  def test_repeated_revocation_still_requires_an_active_owner
    binding = bind
    @repository.revoke(
      id: binding.id,
      actor_user_identity_id: @owner.id,
      revoked_at: Time.utc(2026, 9, 13, 8, 7)
    )

    error = assert_raises(PrismHub::TelegramSurfaceBindingConflictError) do
      @repository.revoke(
        id: binding.id,
        actor_user_identity_id: @member.id,
        revoked_at: Time.utc(2026, 9, 13, 8, 8)
      )
    end

    assert_equal "hub.telegram_surface_binding.owner_required", error.code
  end

  def test_non_owner_cannot_bind_a_surface
    error = assert_raises(PrismHub::TelegramSurfaceBindingConflictError) do
      bind(actor_user_identity_id: @member.id)
    end

    assert_equal "hub.telegram_surface_binding.owner_required", error.code
    assert_equal 0, PrismHub::Adapters::ActiveRecordRecords::TelegramSurfaceBinding.count
  end

  def test_disabled_bot_instance_cannot_receive_a_new_surface_binding
    PrismHub::Adapters::ActiveRecordRecords::BotInstance.where(id: @bot.id).update_all(
      status: "disabled",
      paused_at: nil,
      disabled_at: Time.utc(2026, 9, 13, 8, 9)
    )

    error = assert_raises(PrismHub::TelegramSurfaceBindingConflictError) do
      bind
    end

    assert_equal "hub.telegram_surface_binding.bot_instance_unavailable", error.code
  end

  private

  def bind(
    logical_channel: "digest",
    chat_id: -1001234567890,
    message_thread_id: nil,
    actor_user_identity_id: @owner.id
  )
    @repository.bind(
      workspace_id: @workspace.identifier,
      bot_instance_id: @bot.id,
      logical_channel: logical_channel,
      chat_id: chat_id,
      message_thread_id: message_thread_id,
      actor_user_identity_id: actor_user_identity_id
    )
  end

  def provision_identity(canonical_id)
    @identity_repository.provision(
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: canonical_id)
    )
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
      telegram_surface_bindings
      bot_instance_lifecycle_events
      bot_instances
      workspace_memberships
      provider_identity_bindings
      client_credentials
      capability_grants
      channel_grants
      service_principals
      user_identities
      workspaces
    ].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
