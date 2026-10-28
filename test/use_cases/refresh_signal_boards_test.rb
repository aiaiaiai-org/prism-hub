# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class RefreshSignalBoardsTest < Minitest::Test
  HOME = "861e44067ffffff".freeze
  T0 = Time.utc(2026, 10, 27, 1, 0)

  Subscriptions = Struct.new(:all)

  class Bindings
    def initialize(workspaces)
      @workspaces = workspaces
    end

    def find_by_logical_context(workspace_id:, logical_channel:)
      logical_channel == "alerts" && @workspaces.include?(workspace_id) ? :binding : nil
    end
  end

  class Boards
    attr_reader :states

    def initialize
      @states = {}
    end

    def find(workspace_id:)
      @states[workspace_id]
    end

    def save(state:, previous:)
      @states[state.workspace_id] = state
    end
  end

  class Outbox
    attr_reader :requests

    def initialize
      @requests = []
    end

    def enqueue(request:, available_at:)
      @requests << request
    end
  end

  def setup
    @boards = Boards.new
    @outbox = Outbox.new
    @logger = Logger.new(nil)
  end

  def subscription(workspace)
    PrismHub::Domain::AlertSubscription.new(
      workspace_id: workspace, cell: HOME, categories: %w[drone bomb missile], include_nearby: true,
      updated_at: T0 - 3600
    )
  end

  def track(id)
    {
      "track_id" => id, "kind" => "air.attack_drone", "status" => "active", "count_unknown" => false,
      "position" => {"id" => "p", "name" => "Чернігів"}, "target" => {"id" => "t", "name" => "Київ"},
      "cells" => {"resolution" => 6, "cells" => [HOME]},
      "region_cells" => {"resolution" => 6, "cells" => []},
      "first_at" => (T0 - 600).iso8601, "last_seen_at" => T0.iso8601,
      "evidence" => [{"source_id" => "telegram.channel:kpszsu"}]
    }
  end

  def refresh(workspaces, bound: workspaces, tracks: [track("a")], now: T0)
    use_case = PrismHub::UseCases::RefreshSignalBoards.new(
      subscription_repository: Subscriptions.new(workspaces.map { |workspace| subscription(workspace) }),
      binding_repository: Bindings.new(bound),
      board_repository: @boards,
      outbox_repository: @outbox,
      logger: @logger
    )
    use_case.call(assessments: [], events: [], tracks: tracks, now: now)
  end

  def test_a_threat_queues_a_board_and_a_status_that_carry_their_view
    summary = refresh(["personal-1"])

    board, status = @outbox.requests
    assert_equal %w[signal.board signal.status], @outbox.requests.map { |request| request.artifact["artifact_kind"] }
    assert_equal({"slot" => "board", "revision" => 1, "silent" => true},
      board.view.to_h.slice("slot", "revision", "silent"))
    assert_equal({"slot" => "status", "revision" => 1, "silent" => false},
      status.view.to_h.slice("slot", "revision", "silent"))
    assert_equal({"workspace" => "personal-1", "channel" => "alerts"}, board.routes.first.fetch("logical_context"))
    assert_equal "here", @boards.states.fetch("personal-1").level
    assert_equal 1, summary.alerts
  end

  def test_an_unchanged_board_queues_nothing_and_idempotency_keys_are_stable
    refresh(["personal-1"])
    keys = @outbox.requests.map(&:idempotency_key)
    refresh(["personal-1"], now: T0 + 60)

    assert_equal 2, @outbox.requests.size
    assert_equal keys.uniq.size, keys.size
  end

  def test_a_person_without_a_bound_chat_is_skipped_and_their_state_is_not_advanced
    summary = refresh(%w[personal-1 personal-2], bound: ["personal-2"])

    assert_equal ["personal-2"], @outbox.requests.map(&:workspace).uniq
    assert_nil @boards.states["personal-1"]
    assert_equal 1, summary.skipped[:no_surface]
  end

  def test_one_failing_person_does_not_stop_the_others
    @outbox.define_singleton_method(:enqueue) do |request:, available_at:|
      raise "boom" if request.workspace == "personal-1"

      requests << request
    end

    summary = refresh(%w[personal-1 personal-2])

    assert_equal ["personal-2"], @outbox.requests.map(&:workspace).uniq
    assert_equal 1, summary.skipped[:failed]
  end
end
