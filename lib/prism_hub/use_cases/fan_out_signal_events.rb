# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    # Decides whom to tell about what Prism Signal assessed, and queues one message each.
    #
    # An assessment is a proposal; this is where it becomes a message, so this is where the policy
    # about people lives:
    #
    # * an alert reaches a person standing in the assessment's cells who asked for that class;
    # * a person is told about an assessment once, and about a class no more often than the
    #   cool-down allows;
    # * a retraction reaches only the people who were told the alert, and only while they still
    #   subscribe. It says which other reports of the same class still cover them;
    # * an expiry says nothing. A threat that lapses on its window is not an all-clear, and the
    #   hub never states one;
    # * an event older than the maximum age is history, not news.
    class FanOutSignalEvents
      Summary = Struct.new(:alerts, :retractions, :skipped, keyword_init: true)

      def initialize(subscription_repository:, ledger:, binding_repository:, outbox_repository:, logger:,
        channel: "alerts", max_age_seconds: 1800, cooldown_seconds: 300)
        @subscriptions = subscription_repository
        @ledger = ledger
        @bindings = binding_repository
        @outbox = outbox_repository
        @logger = logger
        @channel = channel
        @max_age = positive(max_age_seconds, "max age")
        @cooldown = positive(cooldown_seconds, "cool-down")
      end

      def call(assessments:, events:, now:)
        summary = Summary.new(alerts: 0, retractions: 0, skipped: Hash.new(0))
        by_id = assessments.to_h { |assessment| [assessment.fetch("assessment_id"), assessment] }
        @bound = {}
        recent(events, now).each do |event|
          assessment = by_id[event.fetch("assessment_id")]
          next summary.skipped[:unknown_assessment] += 1 unless assessment

          case event.fetch("kind")
          when "issued", "superseded" then alert(assessment, event, now, summary)
          when "retracted" then retract(assessment, event, assessments, now, summary)
          end
        end
        summary
      end

      private

      def recent(events, now)
        cutoff = now - @max_age
        events
          .select { |event| %w[issued superseded retracted].include?(event["kind"]) }
          .select { |event| Time.iso8601(event.fetch("effective_at")) >= cutoff }
          .sort_by { |event| [event.fetch("effective_at"), event.fetch("seq")] }
      end

      def alert(assessment, event, now, summary)
        return summary.skipped[:not_active] += 1 unless active?(assessment, now)

        id = assessment.fetch("assessment_id")
        hazard = assessment.fetch("class")
        subscribers = @subscriptions.covering(cells: assessment.dig("cells", "cells"), category: hazard)
        subscribers.each do |subscription|
          next summary.skipped[:nearby_off] += 1 unless wanted?(assessment, subscription)

          workspace = subscription.workspace_id
          next summary.skipped[:already_told] += 1 if @ledger.recorded?(assessment_id: id, workspace_id: workspace, kind: "alert")
          next summary.skipped[:cooldown] += 1 if @ledger.recent_alert?(workspace_id: workspace, hazard_class: hazard, since: now - @cooldown)
          next summary.skipped[:no_surface] += 1 unless bound?(workspace)

          deliver(kind: "alert", workspace: workspace, assessment: assessment, event: event, now: now, summary: summary)
        end
      end

      def retract(assessment, event, assessments, now, summary)
        id = assessment.fetch("assessment_id")
        told = @ledger.alerted_workspaces(assessment_id: id)
        subscriptions = @subscriptions.find_all(workspace_ids: told).to_h { |subscription| [subscription.workspace_id, subscription] }
        summary.skipped[:unsubscribed] += told.length - subscriptions.length
        subscriptions.each do |workspace, subscription|
          next summary.skipped[:already_retracted] += 1 if @ledger.recorded?(assessment_id: id, workspace_id: workspace, kind: "retraction")
          next summary.skipped[:no_surface] += 1 unless bound?(workspace)

          still = still_active(assessments, assessment, subscription, now)
          deliver(kind: "retraction", workspace: workspace, assessment: assessment, event: event, now: now, summary: summary, still_active: still)
        end
      end

      def deliver(kind:, workspace:, assessment:, event:, now:, summary:, still_active: [])
        message = Domain::SignalAlert.new(
          kind: kind,
          workspace: workspace,
          channel: @channel,
          assessment: assessment,
          event: event,
          still_active: still_active
        )
        @outbox.enqueue(request: message.request, available_at: now)
        @ledger.record(
          assessment_id: message.assessment_id,
          workspace_id: workspace,
          hazard_class: message.hazard_class,
          kind: kind,
          event_seq: message.event_seq,
          at: now
        )
        kind == "alert" ? summary.alerts += 1 : summary.retractions += 1
      rescue StandardError => error
        # One person's failure, whatever its cause, must not silence everyone else. Nothing was
        # recorded, so the next pass tries again while the event is still recent.
        @logger.error("signal_delivery_failed kind=#{kind} error_class=#{error.class.name}")
        summary.skipped[:failed] += 1
      end

      def active?(assessment, now)
        assessment["status"] == "active" && Time.iso8601(assessment.fetch("valid_until")) > now
      end

      def wanted?(assessment, subscription)
        assessment["proximity"] != "nearby" || subscription.include_nearby
      end

      # Other reports of the same class that still cover this person, so a retraction never reads
      # as "you are safe" while something else is standing over them.
      def still_active(assessments, retracted, subscription, now)
        assessments
          .select { |other| other.fetch("assessment_id") != retracted.fetch("assessment_id") }
          .select { |other| other["class"] == retracted["class"] && active?(other, now) }
          .select { |other| Array(other.dig("cells", "cells")).include?(subscription.cell) }
          .select { |other| wanted?(other, subscription) }
          .filter_map { |other| other.dig("place", "name") }
          .uniq
          .sort
      end

      def bound?(workspace)
        return @bound[workspace] if @bound.key?(workspace)

        @bound[workspace] = !@bindings.find_by_logical_context(workspace_id: workspace, logical_channel: @channel).nil?
      end

      def positive(value, name)
        number = Integer(value)
        return number if number.positive?

        raise ArgumentError
      rescue ArgumentError, TypeError
        raise PrismHub::ConfigurationError.new("hub.signal.#{name.tr(" ", "_")}.invalid", "#{name} must be a positive number of seconds")
      end
    end
  end
end
