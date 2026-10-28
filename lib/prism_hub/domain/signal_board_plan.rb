# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    # Decides what one person's board and status should say, and how to get them there.
    #
    # A person keeps one board, always: it is posted once, pinned, and from then on only edited
    # without a sound. It says how close the danger is and lists every object the sources reported
    # for their zone (`here`) or their oblast (`region`); between attacks it says there are no new
    # reports, sums up the last attack, and reminds of a position that may be old.
    #
    # During an attack a status says what is coming: it is sent anew, and rings, only when the
    # danger grows (closer, or something new at the same distance), and the status it replaces is
    # deleted; otherwise it is edited quietly. When nothing concerns the person any more the status
    # is deleted with the board's edit, so only the board remains. Nothing says a place is safe.
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
      # A message sent this recently with no receipt yet is still on its way: do not send another.
      PENDING_SECONDS = 120

      Op = Data.define(:slot, :revision, :artifact_kind, :payload, :edit_message_id, :delete_message_ids, :silent,
        :pin)
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
        # A new attack starts a new summary on the same board.
        base = (@state.level == "quiet" && level != "quiet") ? new_episode : @state
        stale = stale_shown(base)
        shown = live.map { |track, _| track.fetch("track_id") } + stale.map { |track| track.fetch("track_id") }
        ended = base.ended_count + (base.shown_track_ids - shown).length
        since = base.episode_started_at || (live.map { |track, _| time(track["first_at"]) }.compact.min || @now unless live.empty?)

        state = base.with(level: level, hazards: hazards, shown_track_ids: shown, ended_count: ended,
          episode_started_at: since)
        status_op, state, gone = status(level, live, grew?(level, hazards), state)
        board_op, state = board(board_payload(level, live, stale, since, ended), state, delete: gone)
        # The status goes with the board's next edit; until that edit is sent it is kept to delete.
        state = state.with(status_message_id: gone.first) if board_op.nil? && gone.any?
        Result.new(ops: [board_op, status_op].compact, state: state)
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
      def stale_shown(state)
        @tracks.select { |track| track["status"] == "stale" && state.shown_track_ids.include?(track["track_id"]) }
      end

      def new_episode
        @state.with(shown_track_ids: [], ended_count: 0, episode_started_at: nil)
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

      def board(payload, state, delete:)
        digest = Digest::SHA256.hexdigest(JSON.generate(payload.except("as_of")))
        if state.board_message_id
          return [nil, state] if digest == state.board_digest && delete.empty?

          send_board(payload, digest, state, edit: state.board_message_id, delete: delete)
        elsif pending?(state.board_sent_at)
          [nil, state]
        else
          send_board(payload, digest, state, edit: nil, delete: delete)
        end
      end

      # A board sent anew is pinned, so it stays on top however much the chat scrolls.
      def send_board(payload, digest, state, edit:, delete:)
        revision = state.board_revision + 1
        op = Op.new(slot: "board", revision: revision, artifact_kind: "signal.board", payload: payload,
          edit_message_id: edit, delete_message_ids: delete, silent: true, pin: edit.nil?)
        [op, state.with(board_revision: revision, board_digest: digest, board_sent_at: @now)]
      end

      # The status, and the ids of a status the board's edit should delete: when it is quiet, a
      # status still on screen goes.
      def status(level, live, grew, state)
        if level == "quiet"
          gone = [state.status_message_id].compact
          return [nil, state.with(status_message_id: nil, status_digest: nil, status_sent_at: nil), gone]
        end

        op, state = status_op(status_payload(level, live), state, grew)
        [op, state, []]
      end

      def status_op(payload, state, grew)
        digest = Digest::SHA256.hexdigest(JSON.generate(payload.except("as_of")))
        if grew
          replace_status(payload, digest, state)
        elsif state.status_message_id
          return [nil, state] if digest == state.status_digest

          send_status(payload, digest, state, edit: state.status_message_id, delete: [], silent: true)
        elsif pending?(state.status_sent_at)
          [nil, state]
        else
          send_status(payload, digest, state, edit: nil, delete: [], silent: true)
        end
      end

      # A new status that rings, and the old one removed.
      def replace_status(payload, digest, state)
        old = [state.status_message_id].compact
        op, state = send_status(payload, digest, state, edit: nil, delete: old, silent: false)
        [op, state.with(status_message_id: nil)]
      end

      def send_status(payload, digest, state, edit:, delete:, silent:)
        revision = state.status_revision + 1
        op = Op.new(slot: "status", revision: revision, artifact_kind: "signal.status", payload: payload,
          edit_message_id: edit, delete_message_ids: delete, silent: silent, pin: false)
        [op, state.with(status_revision: revision, status_digest: digest, status_sent_at: @now)]
      end

      def pending?(sent_at)
        sent_at && (@now - sent_at) < PENDING_SECONDS
      end

      # The position, when it may be old: a quiet board asks whether the person is still there.
      def stale_position
        position_at = @subscription.updated_at
        position_at if (@now - position_at) >= POSITION_STALE_SECONDS
      end

      def board_payload(level, live, stale, since, ended)
        payload = {
          "schema_version" => "prism-hub.signal-board.v1",
          "level" => level,
          "since" => since&.utc&.iso8601,
          "as_of" => @now.iso8601,
          "entries" => entries(live),
          "quiet" => stale_entries(stale),
          "ended" => ended
        }
        position_at = level == "quiet" ? stale_position : nil
        payload["position_at"] = position_at.utc.iso8601 if position_at
        payload
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

      def status_payload(level, live)
        {
          "schema_version" => "prism-hub.signal-status.v1",
          "level" => level,
          "as_of" => @now.iso8601,
          "here" => hazard_counts(live, "here"),
          "region" => hazard_counts(live, "region")
        }
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
