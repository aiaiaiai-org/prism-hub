# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class SignalBoardPlanTest < Minitest::Test
  HOME = "861e44067ffffff"
  ELSEWHERE = "861e4406fffffff"
  T0 = Time.utc(2026, 10, 27, 1, 0)

  def subscription(categories: %w[drone bomb missile], include_nearby: true, updated_at: T0 - 3600)
    PrismHub::Domain::AlertSubscription.new(
      workspace_id: "personal-1", cell: HOME, categories: categories, include_nearby: include_nearby,
      updated_at: updated_at
    )
  end

  def track(id, kind: "air.attack_drone", here: true, region: false, status: "active", count_unknown: false,
    position: "Чернігів", target: "Київ", seen: T0, source: "telegram.channel:kpszsu")
    {
      "track_id" => id, "kind" => kind, "status" => status, "count_unknown" => count_unknown,
      "position" => {"id" => "p:#{position}", "name" => position},
      "target" => target && {"id" => "t:#{target}", "name" => target},
      "cells" => {"resolution" => 6, "cells" => here ? [HOME] : []},
      "region_cells" => {"resolution" => 6, "cells" => region ? [HOME] : []},
      "first_at" => (seen - 600).iso8601, "last_seen_at" => seen.iso8601,
      "evidence" => [{"source_id" => source}]
    }
  end

  def plan(tracks, state: PrismHub::Domain::SignalBoardState.empty("personal-1"), now: T0, sub: subscription)
    PrismHub::Domain::SignalBoardPlan.call(tracks: tracks, subscription: sub, state: state, now: now)
  end

  def receipt(state, board: nil, status: nil)
    state = state.with(board_message_id: board) if board
    state = state.with(status_message_id: status) if status
    state
  end

  def test_nothing_concerns_a_quiet_person_and_nothing_is_sent
    result = plan([track("a", here: false)])
    assert_empty result.ops
    assert_equal "quiet", result.state.level
  end

  def test_the_first_report_posts_a_quiet_board_and_a_status_that_rings
    result = plan([track("a"), track("b"), track("c", kind: "air.jet_drone")])

    board, status = result.ops
    assert_equal ["board", nil, true], [board.slot, board.edit_message_id, board.silent]
    assert_equal ["status", false, []], [status.slot, status.silent, status.delete_message_ids]
    entry = board.payload.fetch("entries").find { |item| item["kind"] == "air.attack_drone" }
    assert_equal({"level" => "here", "count" => 2, "place" => "Чернігів", "target" => "Київ", "source" => "@kpszsu"},
      entry.slice("level", "count", "place", "target", "source"))
    assert_equal "here", status.payload.fetch("level")
    assert_equal [{"kind" => "air.jet_drone", "count" => 1}, {"kind" => "air.attack_drone", "count" => 2}],
      status.payload.fetch("here")
  end

  def test_more_of_the_same_edits_quietly_and_something_closer_or_new_rings
    first = plan([track("a")])
    state = receipt(first.state, board: 10, status: 11)

    more = plan([track("a"), track("b")], state: state, now: T0 + 60)
    assert_equal [["board", 10, true], ["status", 11, true]], more.ops.map { |op| [op.slot, op.edit_message_id, op.silent] }

    state = receipt(more.state, board: 10, status: 11)
    ballistic = plan([track("a"), track("b"), track("x", kind: "air.ballistic_missile")], state: state, now: T0 + 120)
    status = ballistic.ops.find { |op| op.slot == "status" }
    assert_equal [false, nil, [11]], [status.silent, status.edit_message_id, status.delete_message_ids]

    unchanged = plan([track("a")], state: receipt(first.state, board: 10, status: 11), now: T0 + 30)
    assert_empty unchanged.ops, "a report that changes nothing sends nothing"
  end

  def test_the_oblast_is_a_quieter_level_and_coming_closer_rings
    region = plan([track("r", here: false, region: true, position: "Київська область", target: nil)])
    status = region.ops.find { |op| op.slot == "status" }
    assert_equal ["region", false], [status.payload.fetch("level"), status.silent]

    closer = plan([track("r", here: false, region: true), track("h")], state: receipt(region.state, board: 1, status: 2),
      now: T0 + 60)
    status = closer.ops.find { |op| op.slot == "status" }
    assert_equal ["here", false, [2]], [status.payload.fetch("level"), status.silent, status.delete_message_ids]

    off = plan([track("r", here: false, region: true)], sub: subscription(include_nearby: false))
    assert_empty off.ops, "the oblast is nearby, which the person can turn off"
  end

  def test_when_it_all_ends_the_board_closes_and_a_quiet_status_is_never_an_all_clear
    first = plan([track("a"), track("b")])
    state = receipt(first.state, board: 10, status: 11)

    ended = plan([track("a", status: "neutralized", here: false), track("b", status: "cleared", here: false)],
      state: state, now: T0 + 600)

    board, status = ended.ops
    assert_equal [10, 2], [board.edit_message_id, board.payload.fetch("ended")]
    assert_empty board.payload.fetch("entries")
    assert_equal ["quiet", true, [11]], [status.payload.fetch("level"), status.silent, status.delete_message_ids]
    refute status.payload.key?("position_at"), "a fresh position is not mentioned"
    assert_nil ended.state.board_message_id, "the next report starts a new board"
    assert_equal 2, ended.state.board_floor_revision, "receipts for the closed board are ignored"

    again = plan([track("c")], state: receipt(ended.state, status: 12), now: T0 + 1200)
    assert_equal [["board", nil], ["status", nil]], again.ops.map { |op| [op.slot, op.edit_message_id] }
    assert_equal [12], again.ops.last.delete_message_ids, "the quiet status gives way to the new one"
  end

  def test_an_old_position_is_mentioned_only_in_the_quiet_status_and_at_most_daily
    sub = subscription(updated_at: T0 - (4 * 86_400))
    first = plan([track("a")], sub: sub)
    refute first.ops.last.payload.key?("position_at"), "never while the danger is on"

    quiet = plan([], state: receipt(first.state, board: 1, status: 2), now: T0 + 600, sub: sub)
    assert_equal (T0 - (4 * 86_400)).iso8601, quiet.ops.last.payload.fetch("position_at")

    again = plan([track("b")], state: receipt(quiet.state, status: 3), now: T0 + 1200, sub: sub)
    later = plan([], state: receipt(again.state, board: 4, status: 5), now: T0 + 1800, sub: sub)
    refute later.ops.last.payload.key?("position_at"), "once a day"
  end

  def test_a_message_on_its_way_is_not_sent_twice
    first = plan([track("a")])
    soon = plan([track("a"), track("b")], state: first.state, now: T0 + 30)
    assert_empty soon.ops, "no receipt yet, still in the outbox"

    lost = plan([track("a"), track("b")], state: first.state, now: T0 + 600)
    assert_equal [["board", nil], ["status", nil]], lost.ops.map { |op| [op.slot, op.edit_message_id] }
  end

  def test_quiet_tracks_stay_live_and_stale_ones_are_shown_apart_never_as_ended
    first = plan([track("a"), track("b", position: "Бровари", target: nil)])
    state = receipt(first.state, board: 1, status: 2)

    later = plan([track("a", status: "quiet"), track("b", status: "stale", here: false, position: "Бровари", target: nil)],
      state: state, now: T0 + 7200)

    board = later.ops.find { |op| op.slot == "board" }.payload
    assert_equal true, board.fetch("entries").first.fetch("quiet")
    assert_equal "Бровари", board.fetch("quiet").first.fetch("place")
    assert_equal 0, board.fetch("ended")
  end

  def test_categories_filter_and_unknown_counts_are_not_numbers
    only_missiles = plan([track("a")], sub: subscription(categories: %w[missile]))
    assert_empty only_missiles.ops

    unknown = plan([track("a", count_unknown: true), track("b")])
    entry = unknown.ops.first.payload.fetch("entries").first
    assert_nil entry.fetch("count")
  end

  def test_the_rendering_contract_is_met_for_porter
    result = plan([track("a"), track("r", here: false, region: true, position: "Київська область", target: nil)])
    board = result.ops.first.payload
    assert_equal %w[as_of ended entries quiet schema_version since], board.keys.sort
    assert_equal %w[count kind last_seen_at level place quiet source target], board.fetch("entries").first.keys.sort
    assert_equal %w[here region], board.fetch("entries").map { |item| item["level"] }
  end
end
