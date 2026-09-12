# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class GenerateMailDigests
      SCHEMA_VERSION = "prism-hub.mail-digests.v1".freeze
      CHILD_SCHEMA_VERSION = "prism-mail.digest.v1".freeze
      MODE = "extractive".freeze

      def initialize(list_mailboxes:, generate_mail_digest:)
        @list_mailboxes = list_mailboxes
        @generate_mail_digest = generate_mail_digest
      end

      def call(since:, before:, mailbox_ids: nil)
        window = canonical_window(since, before)
        selected_mailboxes = select_mailboxes(@list_mailboxes.call, mailbox_ids)
        digests = selected_mailboxes.map do |mailbox|
          digest = @generate_mail_digest.call(
            mailbox_id: mailbox.id,
            since: window.fetch("since"),
            before: window.fetch("before")
          )
          validate_digest!(digest, mailbox: mailbox, window: window)
          digest
        end
        entries = timeline_entries(selected_mailboxes, digests)

        {
          "schema_version" => SCHEMA_VERSION,
          "mode" => MODE,
          "window" => window,
          "mailbox_count" => selected_mailboxes.length,
          "matched_count" => sum(digests, "matched_count"),
          "selected_count" => sum(digests, "selected_count"),
          "omitted_count" => sum(digests, "omitted_count"),
          "entries" => entries,
          "digests" => selected_mailboxes.zip(digests).map do |mailbox, digest|
            {"mailbox" => mailbox.public_attributes, "digest" => digest}
          end
        }
      end

      private

      def select_mailboxes(mailboxes, requested_ids)
        return mailboxes if requested_ids.nil?

        ids = Array(requested_ids).map { validate_mailbox_id(_1) }
        raise InputError.new("hub.mail.mailboxes.empty", "at least one mailbox must be selected") if ids.empty?
        unless ids.uniq.length == ids.length
          raise InputError.new("hub.mail.mailboxes.duplicate", "mailbox selection must be unique")
        end

        by_id = mailboxes.to_h { |mailbox| [mailbox.id, mailbox] }
        missing = ids.reject { |id| by_id.key?(id) }
        unless missing.empty?
          raise InputError.new(
            "hub.mail.mailbox.not_found",
            "selected mailbox is not visible to the connected credential",
            details: {"mailbox_ids" => missing}
          )
        end

        ids.map { |id| by_id.fetch(id) }
      end

      def validate_mailbox_id(value)
        return value if value.is_a?(String) && value.match?(/\A[^[:cntrl:]\s]{1,100}\z/)

        raise InputError.new("hub.mail.mailbox_id.invalid", "mailbox_id must be a nonblank identifier")
      end

      def canonical_window(since, before_value)
        since_time = parse_timestamp(since, "since")
        before_time = parse_timestamp(before_value, "before")
        unless since_time < before_time
          raise InputError.new("hub.mail.window.invalid", "mail digest since must precede before")
        end

        {"since" => since_time.iso8601, "before" => before_time.iso8601}
      end

      def parse_timestamp(value, label)
        unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
          raise InputError.new("hub.mail.window.invalid", "#{label} must be ISO 8601 with an explicit UTC offset")
        end

        Time.iso8601(value).utc
      rescue ArgumentError
        raise InputError.new("hub.mail.window.invalid", "#{label} must be a valid ISO 8601 timestamp")
      end

      def validate_digest!(digest, mailbox:, window:)
        valid = digest.is_a?(Hash) &&
          digest["schema_version"] == CHILD_SCHEMA_VERSION &&
          digest["mode"] == MODE &&
          digest["mailbox_id"] == mailbox.id &&
          digest["window"] == window &&
          valid_counts?(digest) &&
          valid_entries?(digest, mailbox: mailbox, window: window)
        return if valid

        invalid_digest!
      end

      def valid_counts?(digest)
        counts = %w[matched_count selected_count omitted_count].map { |key| digest[key] }
        return false unless counts.all? { |value| value.is_a?(Integer) && value >= 0 }

        matched, selected, omitted = counts
        matched == selected + omitted
      end

      def valid_entries?(digest, mailbox:, window:)
        entries = digest["entries"]
        return false unless entries.is_a?(Array) && entries.length == digest["selected_count"]

        since_time = Time.iso8601(window.fetch("since"))
        before_time = Time.iso8601(window.fetch("before"))
        entries.all? do |entry|
          valid_entry?(entry, mailbox: mailbox, since_time: since_time, before_time: before_time)
        end
      rescue ArgumentError, KeyError, TypeError
        false
      end

      def valid_entry?(entry, mailbox:, since_time:, before_time:)
        return false unless entry.is_a?(Hash) && entry["kind"] == "source_excerpt"

        evidence = entry["evidence"]
        return false unless evidence.is_a?(Hash)
        return false unless evidence["mailbox_id"] == mailbox.id
        return false unless valid_evidence_id?(evidence["id"])

        received_at = evidence_timestamp(evidence["received_at"])
        received_at >= since_time && received_at < before_time
      rescue ArgumentError, TypeError
        false
      end

      def valid_evidence_id?(value)
        value.is_a?(String) && value.match?(/\A[^[:cntrl:]\s]{1,100}\z/)
      end

      def evidence_timestamp(value)
        unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
          raise ArgumentError
        end

        Time.iso8601(value).utc
      end

      def timeline_entries(mailboxes, digests)
        rows = mailboxes.zip(digests).flat_map do |mailbox, digest|
          digest.fetch("entries").map do |entry|
            evidence = entry.fetch("evidence")
            [
              evidence_timestamp(evidence.fetch("received_at")),
              mailbox.id,
              evidence.fetch("id"),
              {
                "mailbox" => mailbox.public_attributes,
                "kind" => entry.fetch("kind"),
                "evidence" => evidence
              }
            ]
          end
        end

        rows.sort_by { |received_at, mailbox_id, evidence_id, _entry| [-received_at.to_r, mailbox_id, evidence_id] }
          .map(&:last)
      rescue ArgumentError, KeyError, TypeError
        invalid_digest!
      end

      def sum(digests, key)
        digests.sum { |digest| Integer(digest.fetch(key)) }
      rescue ArgumentError, KeyError, TypeError
        invalid_digest!
      end

      def invalid_digest!
        raise ExecutionUnavailableError.new(
          "hub.mail.digest.invalid",
          "Prism Mail returned an invalid digest artifact"
        )
      end
    end
  end
end
