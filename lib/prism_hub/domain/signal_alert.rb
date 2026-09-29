# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    # What one person is told about one assessment: an alert, or the retraction of one they were
    # told about earlier.
    #
    # The artifact is the `signal.alert` payload Porter renders. It carries the words the person
    # must be able to weigh the report by, the source and when it said so, and never a claim the
    # source did not make.
    class SignalAlert
      ARTIFACT_KIND = "signal.alert".freeze
      KINDS = %w[alert retraction].freeze
      CLASSES = %w[drone bomb missile].freeze
      MAX_SOURCES = 3
      MAX_STILL_ACTIVE = 5

      attr_reader :kind, :workspace, :channel, :assessment_id, :hazard_class, :event_seq

      def initialize(kind:, workspace:, channel:, assessment:, event_seq:, still_active: [])
        raise ArgumentError, "unknown alert kind" unless KINDS.include?(kind)

        @kind = kind
        @workspace = workspace
        @channel = channel
        @assessment = assessment
        @assessment_id = assessment.fetch("assessment_id")
        @hazard_class = assessment.fetch("class")
        raise ArgumentError, "unknown hazard class" unless CLASSES.include?(@hazard_class)

        @event_seq = event_seq
        @still_active = still_active
        freeze
      end

      # One entry per person, per assessment, per kind: the same event can never queue twice.
      def idempotency_key
        Digest::SHA256.hexdigest(["signal.alert", assessment_id, kind, workspace].join("\0"))
      end

      def artifact_id
        "signal-alert-#{idempotency_key[0, 40]}"
      end

      def payload
        evidence = Array(@assessment["evidence"])
        {
          "event" => kind,
          "hazard" => {"class" => hazard_class, "kinds" => Array(@assessment["kinds"]).sort},
          "place" => {"name" => @assessment.dig("place", "name")},
          "proximity" => @assessment.fetch("proximity"),
          "likelihood" => @assessment["likelihood"],
          "first_reported_at" => @assessment.fetch("valid_from"),
          "valid_until" => @assessment.fetch("valid_until"),
          "sources" => evidence.last(MAX_SOURCES).map { |item| source(item) },
          "still_active" => @still_active.first(MAX_STILL_ACTIVE)
        }
      end

      def request
        DeliveryRequest.new(
          artifact: {"artifact_id" => artifact_id, "artifact_kind" => ARTIFACT_KIND, "payload" => payload},
          routes: [
            {
              "artifact_kind" => ARTIFACT_KIND,
              "logical_context" => {"workspace" => workspace, "channel" => channel}
            }
          ],
          workspace: workspace,
          channel: channel,
          idempotency_key: idempotency_key
        )
      end

      private

      def source(item)
        {
          "source_id" => item.fetch("source_id"),
          "url" => item["url"],
          "observed_at" => item.fetch("observed_at")
        }
      end
    end
  end
end
