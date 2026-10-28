# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    # What one person was last shown of an attack: which messages hold their board and status,
    # what those said, and how close the danger was. The planner reads it and writes the next one.
    #
    # Message ids arrive later, as receipts from the delivery worker, so a revision counts what
    # was sent and a floor tells a late receipt for a closed board from a live one.
    SignalBoardState = Data.define(
      :workspace_id,
      :board_message_id, :board_revision, :board_floor_revision, :board_digest, :board_sent_at,
      :status_message_id, :status_revision, :status_digest, :status_sent_at,
      :level, :hazards, :shown_track_ids, :ended_count, :episode_started_at, :position_reminded_at
    ) do
      def self.empty(workspace_id)
        new(
          workspace_id: workspace_id,
          board_message_id: nil, board_revision: 0, board_floor_revision: 0, board_digest: nil, board_sent_at: nil,
          status_message_id: nil, status_revision: 0, status_digest: nil, status_sent_at: nil,
          level: "quiet", hazards: [], shown_track_ids: [], ended_count: 0, episode_started_at: nil,
          position_reminded_at: nil
        )
      end
    end
  end
end
