# © 2026 aiaiaiai · aiaiaiai.org

ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require_relative "../test_helper"

class ActiveRecordSignalBoardRepositoryTest < Minitest::Test
  T0 = Time.utc(2026, 10, 27, 1, 0)

  def setup
    clear_tables
    PrismHub::Adapters::ActiveRecordRecords::Workspace.create!(identifier: "personal-a", status: "active")
    @repository = PrismHub::Adapters::ActiveRecordSignalBoardRepository.new
    @empty = PrismHub::Domain::SignalBoardState.empty("personal-a")
  end

  def teardown
    clear_tables
  end

  def test_find_is_nil_until_a_state_is_saved_and_then_round_trips
    assert_nil @repository.find(workspace_id: "personal-a")

    state = @empty.with(
      board_revision: 1, board_digest: "a" * 64, board_sent_at: T0, status_revision: 1, status_sent_at: T0,
      level: "here", hazards: ["air.attack_drone"], shown_track_ids: %w[t1 t2], episode_started_at: T0
    )
    @repository.save(state: state, previous: @empty)

    assert_equal state.to_h, @repository.find(workspace_id: "personal-a").to_h
  end

  def test_a_receipt_sets_the_message_id_and_a_later_save_keeps_it
    sent = @empty.with(board_revision: 1, status_revision: 1, level: "here")
    @repository.save(state: sent, previous: @empty)
    @repository.record(workspace: "personal-a", slot: "board", revision: 1, message_id: 10)
    @repository.record(workspace: "personal-a", slot: "status", revision: 1, message_id: 11)

    # The planner saved again before it saw those receipts: its state still has no message ids.
    @repository.save(state: sent.with(board_revision: 2), previous: sent)

    stored = @repository.find(workspace_id: "personal-a")
    assert_equal [10, 11, 2], [stored.board_message_id, stored.status_message_id, stored.board_revision]
  end

  def test_a_receipt_for_an_older_revision_or_a_closed_board_is_ignored
    @repository.save(state: @empty.with(board_revision: 2, status_revision: 3), previous: @empty)
    @repository.record(workspace: "personal-a", slot: "board", revision: 1, message_id: 10)
    @repository.record(workspace: "personal-a", slot: "status", revision: 2, message_id: 11)
    assert_equal [nil, nil], ids

    closed = @empty.with(board_revision: 2, board_floor_revision: 2, status_revision: 3)
    @repository.save(state: closed, previous: @empty)
    @repository.record(workspace: "personal-a", slot: "board", revision: 2, message_id: 12)
    assert_equal [nil, nil], ids
  end

  def test_the_planner_clearing_a_message_id_wins
    sent = @empty.with(status_revision: 1, status_message_id: 11)
    @repository.save(state: sent, previous: @empty)
    @repository.save(state: sent.with(status_revision: 2, status_message_id: nil), previous: sent)

    assert_equal [nil, nil], ids
  end

  private

  def ids
    stored = @repository.find(workspace_id: "personal-a")
    [stored.board_message_id, stored.status_message_id]
  end

  def clear_tables
    connection = ActiveRecord::Base.connection
    %w[signal_boards workspaces].each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}") if connection.data_source_exists?(table)
    end
  end
end
