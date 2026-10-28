# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    # Keeps every person's live board and status in step with what Prism Signal tracks.
    #
    # This replaces one message per report (FanOutSignalEvents) with two messages per person:
    # a board edited in place and a status that rings only when the danger grows. What they say
    # and when they ring is Domain::SignalBoardPlan's; this queues the deliveries, each with the
    # view the bot needs to edit, delete or stay silent, and saves the new state.
    class RefreshSignalBoards
      Summary = Struct.new(:alerts, :retractions, :skipped, keyword_init: true)

      def initialize(subscription_repository:, binding_repository:, board_repository:, outbox_repository:, logger:,
        channel: "alerts")
        @subscriptions = subscription_repository
        @bindings = binding_repository
        @boards = board_repository
        @outbox = outbox_repository
        @logger = logger
        @channel = channel
      end

      # `assessments` and `events` are accepted so this stands in for the per-report fan-out.
      def call(assessments:, events:, tracks:, now:)
        summary = Summary.new(alerts: 0, retractions: 0, skipped: Hash.new(0))
        @subscriptions.all.each { |subscription| refresh(subscription, tracks, now, summary) }
        summary
      end

      private

      def refresh(subscription, tracks, now, summary)
        workspace = subscription.workspace_id
        previous = @boards.find(workspace_id: workspace) || Domain::SignalBoardState.empty(workspace)
        result = Domain::SignalBoardPlan.call(tracks: tracks, subscription: subscription, state: previous, now: now)
        return if result.ops.empty? && result.state == previous
        return summary.skipped[:no_surface] += 1 if result.ops.any? && !bound?(workspace)

        result.ops.each { |op| @outbox.enqueue(request: request(workspace, op), available_at: now) }
        @boards.save(state: result.state, previous: previous)
        summary.alerts += result.ops.count { |op| op.slot == "status" && !op.silent }
      rescue StandardError => error
        # One person's failure must not keep everyone else's board still.
        @logger.error("signal_board_failed error_class=#{error.class.name}")
        summary.skipped[:failed] += 1
      end

      def request(workspace, op)
        key = Digest::SHA256.hexdigest(["signal.view", workspace, op.slot, op.revision].join("\0"))
        Domain::DeliveryRequest.new(
          artifact: {"artifact_id" => "signal-#{op.slot}-#{key[0, 40]}", "artifact_kind" => op.artifact_kind,
                     "payload" => op.payload},
          routes: [{"artifact_kind" => op.artifact_kind,
                    "logical_context" => {"workspace" => workspace, "channel" => @channel}}],
          workspace: workspace,
          channel: @channel,
          idempotency_key: key,
          view: Domain::DeliveryView.new(
            edit_message_id: op.edit_message_id, delete_message_ids: op.delete_message_ids, silent: op.silent,
            pin: op.pin, slot: op.slot, revision: op.revision
          )
        )
      end

      def bound?(workspace)
        !@bindings.find_by_logical_context(workspace_id: workspace, logical_channel: @channel).nil?
      end
    end
  end
end
