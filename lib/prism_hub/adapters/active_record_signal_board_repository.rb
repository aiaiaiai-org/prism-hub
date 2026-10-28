# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class ActiveRecordSignalBoardRepository < Ports::SignalBoardRepository
      PLANNED = %i[
        board_revision board_floor_revision board_digest board_sent_at
        status_revision status_digest status_sent_at
        level hazards shown_track_ids ended_count episode_started_at position_reminded_at
      ].freeze

      def find(workspace_id:)
        record = ActiveRecordRecords::SignalBoard.joins(:workspace).find_by(workspaces: {identifier: workspace_id})
        record && to_domain(record, workspace_id)
      end

      def save(state:, previous:)
        ::ActiveRecord::Base.transaction do
          record = ActiveRecordRecords::SignalBoard.lock.joins(:workspace)
            .find_by(workspaces: {identifier: state.workspace_id})
          record ||= ActiveRecordRecords::SignalBoard.new(workspace: workspace!(state.workspace_id))
          attributes = PLANNED.to_h { |name| [name, state.public_send(name)] }
          # The planner only ever clears a message id; a receipt sets one. Leave it to the receipt
          # unless the planner changed it.
          attributes[:board_message_id] = state.board_message_id if state.board_message_id != previous.board_message_id
          attributes[:status_message_id] = state.status_message_id if state.status_message_id != previous.status_message_id
          record.update!(attributes)
        end
        nil
      end

      # Records the message a board or status now lives in, unless a newer revision was sent since
      # or the board was closed.
      def record(workspace:, slot:, revision:, message_id:)
        scope = ActiveRecordRecords::SignalBoard.where(
          workspace_id: ActiveRecordRecords::Workspace.where(identifier: workspace).select(:id)
        )
        case slot
        when "board"
          scope.where(board_revision: revision).where("board_floor_revision < ?", revision)
            .update_all(board_message_id: message_id, updated_at: Time.now.utc)
        when "status"
          scope.where(status_revision: revision).update_all(status_message_id: message_id, updated_at: Time.now.utc)
        end
        nil
      end

      private

      def workspace!(identifier)
        ActiveRecordRecords::Workspace.find_by!(identifier: identifier)
      end

      def to_domain(record, workspace_id)
        Domain::SignalBoardState.new(
          workspace_id: workspace_id,
          board_message_id: record.board_message_id,
          board_revision: record.board_revision,
          board_floor_revision: record.board_floor_revision,
          board_digest: record.board_digest,
          board_sent_at: record.board_sent_at&.to_time&.utc,
          status_message_id: record.status_message_id,
          status_revision: record.status_revision,
          status_digest: record.status_digest,
          status_sent_at: record.status_sent_at&.to_time&.utc,
          level: record.level,
          hazards: record.hazards,
          shown_track_ids: record.shown_track_ids,
          ended_count: record.ended_count,
          episode_started_at: record.episode_started_at&.to_time&.utc,
          position_reminded_at: record.position_reminded_at&.to_time&.utc
        )
      end
    end
  end
end
