# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    # Decides what one person's board and status should say, and how to get them there.
    #
    # During an attack a person keeps two messages instead of one per report. The board lists
    # every object the sources reported for their zone (`here`) or their oblast (`region`), and is
    # edited in place without a sound. The status says how close the danger is: it is sent anew,
    # and rings, only when the danger grows (closer, or something new at the same distance), and
    # the status it replaces is deleted; otherwise it is edited quietly. When nothing concerns the
    # person any more the board gets its final edit and a quiet status says the sources went
    # quiet, never that the place is safe. That quiet status is the one place an old position is
    # mentioned.
    #
    # Pure: tracks, the subscription, the previous state and the time in, operations and the next
    # state out.
    class SignalBoardPlan
      LEVELS = {"quiet" => 0, "region" => 1, "here" => 2}.freeze
      LIVE = %w[active quiet].freeze
      KIND_ORDER = %w[air.ballistic_missile air.missile air.jet_drone air.attack_drone air.guided_bomb].freeze
      CLASSES = {
        "air.ballistic_missile" => "missile", "air.missile" => "missile",
        "air.jet_drone" => "drone", "air.attack_drone" => "drone", "air.guided_bomb" => "bomb"
      }.freeze
      CHANNEL = /\Atelegram\.channel:([A-Za-z][A-Za-z0-9_]{3,31})\z/
      POSITION_STALE_SECONDS = 3 * 86_400
      REMIND_EVERY_SECONDS = 86_400
      # A message sent this recently with no receipt yet is still on its way: do not send another.
      PENDING_SECONDS = 120

      Op = Data.define(:slot, :revision, :artifact_kind, :payload, :edit_message_id, :delete_message_ids, :silent)
      Result = Data.define(:ops, :state)

      def self.call(tracks:, subscription:, state:, now:)
        new(tracks: tracks, subscription: subscription, state: state, now: now).call
      end

      def initialize(tracks:, subscription:, state:, now:)
        @tracks = tracks
        @subscription = subscription
        @state = state
        @now = now.utc
      end

      def call
        live = relevant
        level, hazards = alarm(live)
        return Result.new(ops: [], state: @state) if level == "quiet" && @state.level == "quiet"

        stale = stale_shown
        shown = live.map { |track, _| track.fetch("track_id") } + stale.map { |track| track.fetch("track_id") }
        ended = @state.ended_count + (@state.shown_track_ids - shown).length
        since = @state.episode_started_at || live.map { |track, _| time(track["first_at"]) }.compact.min || @now
        closing = level == "quiet"
        grew = grew?(level, hazards)

        state = @state.with(level: level, hazards: hazards, shown_track_ids: shown, ended_count: ended,
          episode_started_at: since)
        ops = []
        board_op, state = board(board_payload(live, stale, since, ended), state)
        ops << board_op if board_op
        status_op, state = status(level, live, closing, grew, state)
        ops << status_op if status_op
        state = close(state) if closing
        Result.new(ops: ops, state: state)
      end

      private

      # Live tracks that concern the person, each with its level.
      def relevant
        @tracks.filter_map do |track|
          next unless LIVE.include?(track["status"])
          next unless @subscription.categories.include?(CLASSES[track["kind"]])

          if cells(track, "cells").include?(@subscription.cell)
            [track, "here"]
          elsif @subscription.include_nearby && cells(track, "region_cells").include?(@subscription.cell)
            [track, "region"]
          end
        end
      end

      # Tracks the person was shown that went quiet for long: still shown apart, never as ended.
      def stale_shown
        @tracks.select { |track| track["status"] == "stale" && @state.shown_track_ids.include?(track["track_id"]) }
      end

      def cells(track, key)
        Array(track.dig(key, "cells"))
      end

      def alarm(live)
        return ["quiet", []] if live.empty?

        level = live.map { |_, level| level }.max_by { |value| LEVELS.fetch(value) }
        hazards = live.select { |_, value| value == level }.map { |track, _| track["kind"] }.uniq
        [level, sort_kinds(hazards)]
      end

      def grew?(level, hazards)
        before = LEVELS.fetch(@state.level)
        now = LEVELS.fetch(level)
        now > before || (now == before && now.positive? && !(hazards - @state.hazards).empty?)
      end

      def board(payload, state)
        digest = Digest::SHA256.hexdigest(JSON.generate(payload.except("as_of")))
        if state.board_message_id
          return [nil, state] if digest == state.board_digest

          send_board(payload, digest, state, edit: state.board_message_id)
        elsif pending?(state.board_sent_at)
          [nil, state]
        else
          send_board(payload, digest, state, edit: nil)
        end
      end

      def send_board(payload, digest, state, edit:)
        revision = state.board_revision + 1
        op = Op.new(slot: "board", revision: revision, artifact_kind: "signal.board", payload: payload,
          edit_message_id: edit, delete_message_ids: [], silent: true)
        [op, state.with(board_revision: revision, board_digest: digest, board_sent_at: @now)]
      end

      def status(level, live, closing, grew, state)
        reminder = closing ? reminder_at : nil
        payload = status_payload(level, live, reminder)
        digest = Digest::SHA256.hexdigest(JSON.generate(payload.except("as_of")))
        state = state.with(position_reminded_at: @now) if reminder
        if grew || closing
          replace_status(payload, digest, state, silent: closing)
        elsif state.status_message_id
          return [nil, state] if digest == state.status_digest

          send_status(payload, digest, state, edit: state.status_message_id, delete: [], silent: true)
        elsif pending?(state.status_sent_at)
          [nil, state]
        else
          send_status(payload, digest, state, edit: nil, delete: [], silent: true)
        end
      end

      # A new status, and the old one removed: it rings unless it only says the sources went quiet.
      def replace_status(payload, digest, state, silent:)
        old = [state.status_message_id].compact
        op, state = send_status(payload, digest, state, edit: nil, delete: old, silent: silent)
        [op, state.with(status_message_id: nil)]
      end

      def send_status(payload, digest, state, edit:, delete:, silent:)
        revision = state.status_revision + 1
        op = Op.new(slot: "status", revision: revision, artifact_kind: "signal.status", payload: payload,
          edit_message_id: edit, delete_message_ids: delete, silent: silent)
        [op, state.with(status_revision: revision, status_digest: digest, status_sent_at: @now)]
      end

      # The attack is over as far as the sources say: the next report starts a new board. A late
      # receipt for this board must not bring it back.
      def close(state)
        state.with(board_message_id: nil, board_floor_revision: state.board_revision, board_digest: nil,
          board_sent_at: nil, shown_track_ids: [], ended_count: 0, episode_started_at: nil, hazards: [])
      end

      def pending?(sent_at)
        sent_at && (@now - sent_at) < PENDING_SECONDS
      end

      def reminder_at
        position_at = @subscription.updated_at
        return nil if (@now - position_at) < POSITION_STALE_SECONDS

        reminded = @state.position_reminded_at
        return nil if reminded && (@now - reminded) < REMIND_EVERY_SECONDS

        position_at
      end

      def board_payload(live, stale, since, ended)
        {
          "schema_version" => "prism-hub.signal-board.v1",
          "since" => since.utc.iso8601,
          "as_of" => @now.iso8601,
          "entries" => entries(live),
          "quiet" => stale_entries(stale),
          "ended" => ended
        }
      end

      def entries(live)
        live
          .group_by { |track, level| [level, track["kind"], place(track, "position"), place(track, "target")] }
          .map { |(level, kind, position, target), group| entry(level, kind, position, target, group.map(&:first)) }
          .sort_by.with_index { |item, index| [-LEVELS.fetch(item["level"]), -time(item["last_seen_at"]).to_i, index] }
      end

      def entry(level, kind, position, target, tracks)
        newest = tracks.max_by { |track| track["last_seen_at"].to_s }
        {
          "level" => level, "kind" => kind, "count" => count(tracks),
          "place" => position, "target" => (target == position ? nil : target),
          "last_seen_at" => time(newest["last_seen_at"]).iso8601,
          "source" => source(newest), "quiet" => tracks.all? { |track| track["status"] == "quiet" }
        }
      end

      def stale_entries(stale)
        stale.group_by { |track| [track["kind"], place(track, "position")] }.map do |(kind, position), group|
          newest = group.max_by { |track| track["last_seen_at"].to_s }
          {"kind" => kind, "count" => count(group), "place" => position,
           "last_seen_at" => time(newest["last_seen_at"]).iso8601}
        end
      end

      def status_payload(level, live, reminder)
        payload = {
          "schema_version" => "prism-hub.signal-status.v1",
          "level" => level,
          "as_of" => @now.iso8601,
          "here" => hazard_counts(live, "here"),
          "region" => hazard_counts(live, "region")
        }
        payload["position_at"] = reminder.utc.iso8601 if reminder
        payload
      end

      def hazard_counts(live, level)
        groups = live.select { |_, value| value == level }.map(&:first).group_by { |track| track["kind"] }
        sort_kinds(groups.keys).map { |kind| {"kind" => kind, "count" => count(groups.fetch(kind))} }
      end

      # How many objects, or nil when any report never said: "at least one" is not a number.
      def count(tracks)
        tracks.any? { |track| track["count_unknown"] } ? nil : tracks.length
      end

      def place(track, key)
        track.dig(key, "name")
      end

      def source(track)
        last = Array(track["evidence"]).last
        match = CHANNEL.match(last&.fetch("source_id", nil).to_s)
        match && "@#{match[1]}"
      end

      def sort_kinds(kinds)
        kinds.sort_by { |kind| KIND_ORDER.index(kind) || KIND_ORDER.length }
      end

      def time(value)
        value && Time.iso8601(value.to_s).utc
      end
    end
  end
end
