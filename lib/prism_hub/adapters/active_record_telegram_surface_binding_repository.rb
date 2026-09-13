# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class ActiveRecordTelegramSurfaceBindingRepository < Ports::TelegramSurfaceBindingRepository
      STATUS_ACTIVE = "active".freeze
      STATUS_REVOKED = "revoked".freeze
      ROLE_OWNER = "owner".freeze

      def bind(
        workspace_id:,
        bot_instance_id:,
        logical_channel:,
        chat_id:,
        message_thread_id:,
        actor_user_identity_id:
      )
        candidate = candidate_binding(
          workspace_id: workspace_id,
          bot_instance_id: bot_instance_id,
          logical_channel: logical_channel,
          chat_id: chat_id,
          message_thread_id: message_thread_id,
          actor_user_identity_id: actor_user_identity_id
        )

        ::ActiveRecord::Base.transaction do
          workspace, bot_instance, actor = locked_context!(candidate)
          logical = active_logical_binding(workspace, candidate.logical_channel, lock: true)
          surface = active_surface_binding(
            bot_instance,
            candidate.chat_id,
            candidate.message_thread_id,
            lock: true
          )
          return verify_existing!(logical, candidate) if logical
          return verify_existing!(surface, candidate) if surface

          to_domain(
            ActiveRecordRecords::TelegramSurfaceBinding.create!(
              workspace: workspace,
              bot_instance: bot_instance,
              logical_channel: candidate.logical_channel,
              chat_id: candidate.chat_id,
              message_thread_id: candidate.message_thread_id,
              created_by_user_identity: actor,
              status: STATUS_ACTIVE
            )
          )
        end
      rescue ::ActiveRecord::RecordNotUnique
        verify_concurrent_bind!(candidate)
      end

      def find_by_logical_context(workspace_id:, logical_channel:)
        workspace_ref = reference(workspace_id, "workspace_id")
        logical = logical_channel_value(logical_channel)
        record = binding_scope.joins(:workspace).find_by(
          workspaces: {identifier: workspace_ref},
          logical_channel: logical,
          status: STATUS_ACTIVE
        )
        record && to_domain(record)
      end

      def find_by_surface(bot_instance_id:, chat_id:, message_thread_id:)
        bot_ref = reference(bot_instance_id, "bot_instance_id")
        chat = chat_id_value(chat_id)
        thread = thread_id_value(message_thread_id)
        record = binding_scope.find_by(
          bot_instance_id: bot_ref,
          chat_id: chat,
          message_thread_id: thread,
          status: STATUS_ACTIVE
        )
        record && to_domain(record)
      end

      def revoke(id:, actor_user_identity_id:, revoked_at:)
        binding_ref = reference(id, "id")
        actor_ref = reference(actor_user_identity_id, "actor_user_identity_id")
        timestamp = normalized_timestamp(revoked_at)

        ::ActiveRecord::Base.transaction do
          record = binding_scope.lock.find_by(id: binding_ref)
          unless record
            raise TelegramSurfaceBindingNotFoundError.new(
              "hub.telegram_surface_binding.not_found",
              "Telegram surface binding was not found"
            )
          end

          actor = locked_owner!(record.workspace, actor_ref)
          if record.status == STATUS_ACTIVE
            record.update!(
              status: STATUS_REVOKED,
              revoked_at: timestamp,
              revoked_by_user_identity: actor
            )
          end
          to_domain(record)
        end
      end

      private

      def candidate_binding(**attributes)
        Domain::TelegramSurfaceBinding.new(
          id: "candidate",
          workspace_id: attributes.fetch(:workspace_id),
          bot_instance_id: attributes.fetch(:bot_instance_id),
          logical_channel: attributes.fetch(:logical_channel),
          chat_id: attributes.fetch(:chat_id),
          message_thread_id: attributes.fetch(:message_thread_id),
          created_by_user_identity_id: attributes.fetch(:actor_user_identity_id),
          status: STATUS_ACTIVE
        )
      end

      def locked_context!(candidate)
        workspace = ActiveRecordRecords::Workspace.lock.find_by(identifier: candidate.workspace_id)
        unless workspace&.status == STATUS_ACTIVE
          raise TelegramSurfaceBindingConflictError.new(
            "hub.telegram_surface_binding.workspace_unavailable",
            "Telegram surface binding requires an active workspace"
          )
        end

        bot_instance = ActiveRecordRecords::BotInstance.lock.find_by(
          id: candidate.bot_instance_id,
          workspace: workspace
        )
        unless bot_instance && bot_instance.status != "disabled"
          raise TelegramSurfaceBindingConflictError.new(
            "hub.telegram_surface_binding.bot_instance_unavailable",
            "Telegram surface binding requires a non-disabled bot instance in the workspace"
          )
        end

        actor = locked_owner!(workspace, candidate.created_by_user_identity_id)
        [workspace, bot_instance, actor]
      end

      def locked_owner!(workspace, actor_id)
        actor = ActiveRecordRecords::UserIdentity.lock.find_by(id: actor_id, status: STATUS_ACTIVE)
        membership = actor && ActiveRecordRecords::WorkspaceMembership.lock.find_by(
          workspace: workspace,
          user_identity: actor,
          status: STATUS_ACTIVE,
          role: ROLE_OWNER
        )
        return actor if membership

        raise TelegramSurfaceBindingConflictError.new(
          "hub.telegram_surface_binding.owner_required",
          "Telegram surface bindings may only be changed by an active workspace owner"
        )
      end

      def active_logical_binding(workspace, logical_channel, lock: false)
        scope = ActiveRecordRecords::TelegramSurfaceBinding.where(
          workspace: workspace,
          logical_channel: logical_channel,
          status: STATUS_ACTIVE
        )
        scope = scope.lock if lock
        scope.first
      end

      def active_surface_binding(bot_instance, chat_id, message_thread_id, lock: false)
        scope = ActiveRecordRecords::TelegramSurfaceBinding.where(
          bot_instance: bot_instance,
          chat_id: chat_id,
          message_thread_id: message_thread_id,
          status: STATUS_ACTIVE
        )
        scope = scope.lock if lock
        scope.first
      end

      def verify_existing!(record, candidate)
        exact = record.workspace.identifier == candidate.workspace_id &&
          record.bot_instance_id == candidate.bot_instance_id &&
          record.logical_channel == candidate.logical_channel &&
          record.chat_id == candidate.chat_id &&
          record.message_thread_id == candidate.message_thread_id
        return to_domain(record) if exact

        code = if record.workspace.identifier == candidate.workspace_id &&
            record.logical_channel == candidate.logical_channel
          "hub.telegram_surface_binding.logical_context_taken"
        else
          "hub.telegram_surface_binding.surface_taken"
        end
        raise TelegramSurfaceBindingConflictError.new(
          code,
          "Telegram surface binding conflicts with an existing active binding"
        )
      end

      def verify_concurrent_bind!(candidate)
        workspace = ActiveRecordRecords::Workspace.find_by(identifier: candidate.workspace_id)
        bot_instance = ActiveRecordRecords::BotInstance.find_by(id: candidate.bot_instance_id)
        logical = workspace && active_logical_binding(workspace, candidate.logical_channel)
        surface = bot_instance && active_surface_binding(
          bot_instance,
          candidate.chat_id,
          candidate.message_thread_id
        )
        record = logical || surface
        return verify_existing!(record, candidate) if record

        raise TelegramSurfaceBindingConflictError.new(
          "hub.telegram_surface_binding.conflict",
          "Telegram surface binding could not be persisted"
        )
      end

      def binding_scope
        ActiveRecordRecords::TelegramSurfaceBinding.includes(
          :workspace,
          :bot_instance,
          :created_by_user_identity,
          :revoked_by_user_identity
        )
      end

      def logical_channel_value(value)
        Domain::TelegramSurfaceBinding.new(
          id: "candidate",
          workspace_id: "workspace",
          bot_instance_id: "bot-instance",
          logical_channel: value,
          chat_id: 1,
          created_by_user_identity_id: "actor",
          status: STATUS_ACTIVE
        ).logical_channel
      end

      def chat_id_value(value)
        Domain::TelegramSurfaceBinding.new(
          id: "candidate",
          workspace_id: "workspace",
          bot_instance_id: "bot-instance",
          logical_channel: "channel",
          chat_id: value,
          created_by_user_identity_id: "actor",
          status: STATUS_ACTIVE
        ).chat_id
      end

      def thread_id_value(value)
        Domain::TelegramSurfaceBinding.new(
          id: "candidate",
          workspace_id: "workspace",
          bot_instance_id: "bot-instance",
          logical_channel: "channel",
          chat_id: 1,
          message_thread_id: value,
          created_by_user_identity_id: "actor",
          status: STATUS_ACTIVE
        ).message_thread_id
      end

      def reference(value, field)
        string = String(value)
        return string if Domain::Channel::REFERENCE_PATTERN.match?(string)

        raise ArgumentError, "#{field} must be a non-empty stable reference"
      end

      def normalized_timestamp(value)
        return value.utc if value.is_a?(Time)

        raise ArgumentError, "revoked_at must be a Time"
      end

      def to_domain(record)
        Domain::TelegramSurfaceBinding.new(
          id: record.id,
          workspace_id: record.workspace.identifier,
          bot_instance_id: record.bot_instance_id,
          logical_channel: record.logical_channel,
          chat_id: record.chat_id,
          message_thread_id: record.message_thread_id,
          created_by_user_identity_id: record.created_by_user_identity_id,
          status: record.status,
          revoked_at: record.revoked_at&.to_time&.utc,
          revoked_by_user_identity_id: record.revoked_by_user_identity_id
        )
      end
    end
  end
end
