# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Ports
    # Reading sources and turning what they said into assessments. Everything here is Prism
    # Signal's business; the hub only decides whom to tell.
    class SignalGateway
      Polled = Struct.new(:evidence, keyword_init: true)
      Assessed = Struct.new(:assessments, :events, keyword_init: true)

      # Evidence from `source` newer than `after` (an opaque cursor, nil for the first read).
      def poll(source:, after:)
        raise NotImplementedError
      end

      # Assessments and their events for a window of evidence, as of `evaluation_time`.
      def assess(evidence:, evaluation_time:)
        raise NotImplementedError
      end
    end
  end
end
