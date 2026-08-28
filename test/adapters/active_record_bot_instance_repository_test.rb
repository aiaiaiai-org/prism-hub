# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordBotInstanceRepositoryTest < Minitest::Test
  def setup
    clear_tables
    @identity_repository = PrismHub::Adapters::ActiveRecordUserIdentityRepository.new
    @membership_repository = PrismHub::Adapters::ActiveRecordWorkspaceMembershipRepository.new
    @repository = PrismHub::Adapters::ActiveRecordBotInstanceRepository.new
    @principal = PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal.create!(
      identifier: "telegram-bot",
      status: "active"
    )
    @workspace = create_workspace("personal-a")
    @identity = provision_identity("0xuser-a")
    @membership_repository.grant(
      user_identity: @identity,
      workspace_id: @workspace.identifier,
      role: "owner"
    )
  end

  def teardown
    clear_tables
  end

  def test_ensure_is_idempotent_and_records_one_created_event
    first_time = Time.utc(2026, 8, 28, 3, 10)
    second_time = Time.utc(2026, 8, 28, 3, 11)

    first = ensure_instance(first_time)
    second = ensure_instance(second_time)

    assert_equal first.id, second.id
    assert_equal "active", second.status
    assert_equal 1, PrismHub::Adapters::ActiveRecordRecords::BotInstance.count
    events = PrismHub::Adapters::ActiveRecordRecords::BotInstanceLifecycleEvent.all
    assert_equal 1, events.length
    assert_equal "created", events.first.action
    assert_equal first_time, events.first.occurred_at.to_time.utc
  end

  def test_pause_is_idempotent_and_preserves_first_pause_timestamp
    ensure_instance(Time.utc(2026, 8, 28, 3, 12))
    first_time = Time.utc(2026, 8, 28, 3, 13)
    second_time = Time.utc(2026, 8, 28, 3, 14)

    first = pause_instance(first_time)
    second = pause_instance(second_time)

    assert first.paused?
    assert_equal first_time, first.paused_at
    assert_equal first_time, second.paused_at
    events = PrismHub::Adapters::ActiveRecordRecords::BotInstanceLifecycleEvent.order(:occurred_at)
    assert_equal %w[created paused], events.map(&:action)
  end

  def test_resume_restores_active_state_and_records_transition
    ensure_instance(Time.utc(2026, 8, 28, 3, 15))
    pause_instance(Time.utc(2026, 8, 28, 3, 16))

    instance = @repository.resume(
      principal_id: @principal.identifier,
      workspace_id: @workspace.identifier,
      actor_user_identity_id: @identity.id,
      occurred_at: Time.utc(2026, 8, 28, 3, 17)
    )

    assert instance.active?
    assert_nil instance.paused_at
    events = PrismHub::Adapters::ActiveRecordRecords::BotInstanceLifecycleEvent.order(:occurred_at)
    assert_equal %w[created paused resumed], events.map(&:action)
  end

  def test_owner_is_rechecked_inside_each_mutation
    ensure_instance(Time.utc(2026, 8, 28, 3, 18))
    PrismHub::Adapters::ActiveRecordRecords::WorkspaceMembership.update_all(role: "member")

    error = assert_raises(PrismHub::BotInstanceConflictError) do
      pause_instance(Time.utc(2026, 8, 28, 3, 19))
    end

    assert_equal "hub.bot_instance.owner_required", error.code
  end

  def test_disabled_instance_cannot_be_resumed_by_normal_lifecycle
    ensure_instance(Time.utc(2026, 8, 28, 3, 20))
    PrismHub::Adapters::ActiveRecordRecords::BotInstance.update_all(
      status: "disabled",
      paused_at: nil,
      disabled_at: Time.utc(2026, 8, 28, 3, 21)
    )

    error = assert_raises(PrismHub::BotInstanceConflictError) do
      @repository.resume(
        principal_id: @principal.identifier,
        workspace_id: @workspace.identifier,
        actor_user_identity_id: @identity.id,
        occurred_at: Time.utc(2026, 8, 28, 3, 22)
      )
    end

    assert_equal "hub.bot_instance.disabled", error.code
  end

  def test_one_machine_principal_has_independent_user_workspace_instances
    second_workspace = create_workspace("personal-b")
    second_identity = provision_identity("0xuser-b")
    @membership_repository.grant(
      user_identity: second_identity,
      workspace_id: second_workspace.identifier,
      role: "owner"
    )
    ensure_instance(Time.utc(2026, 8, 28, 3, 23))
    @repository.ensure(
      principal_id: @principal.identifier,
      workspace_id: second_workspace.identifier,
      actor_user_identity_id: second_identity.id,
      occurred_at: Time.utc(2026, 8, 28, 3, 24)
    )

    pause_instance(Time.utc(2026, 8, 28, 3, 25))

    first = @repository.find(principal_id: @principal.identifier, workspace_id: @workspace.identifier)
    second = @repository.find(principal_id: @principal.identifier, workspace_id: second_workspace.identifier)
    assert first.paused?
    assert second.active?
  end

  private

  def ensure_instance(time)
    @repository.ensure(
      principal_id: @principal.identifier,
      workspace_id: @workspace.identifier,
      actor_user_identity_id: @identity.id,
      occurred_at: time
    )
  end

  def pause_instance(time)
    @repository.pause(
      principal_id: @principal.identifier,
      workspace_id: @workspace.identifier,
      actor_user_identity_id: @identity.id,
      occurred_at: time
    )
  end

  def create_workspace(identifier)
    PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(identifier: identifier, status: "active")
  end

  def provision_identity(canonical_id)
    @identity_repository.provision(
      canonical_identity: PrismHub::Domain::CanonicalIdentityRef.new(type: "person", id: canonical_id)
    )
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[
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
