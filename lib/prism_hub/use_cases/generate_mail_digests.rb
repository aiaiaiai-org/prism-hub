# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class GenerateMailDigests
      SCHEMA_VERSION = "prism-hub.mail-digests.v1".freeze

      def initialize(list_mailboxes:, generate_mail_digest:)
        @list_mailboxes = list_mailboxes
        @generate_mail_digest = generate_mail_digest
      end

      def call(since:, before:, mailbox_ids: nil)
        selected_mailboxes = select_mailboxes(@list_mailboxes.call, mailbox_ids)
        digests = selected_mailboxes.map do |mailbox|
          @generate_mail_digest.call(mailbox_id: mailbox.id, since: since, before: before)
        end

        window = digests.empty? ? canonical_window(since, before) : digests.first.fetch("window")
        {
          "schema_version" => SCHEMA_VERSION,
          "mode" => "extractive",
          "window" => window,
          "mailbox_count" => selected_mailboxes.length,
          "matched_count" => sum(digests, "matched_count"),
          "selected_count" => sum(digests, "selected_count"),
          "omitted_count" => sum(digests, "omitted_count"),
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
        raise InputError.new("hub.mail.mailboxes.duplicate", "mailbox selection must be unique") unless ids.uniq.length == ids.length

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

      def sum(digests, key)
        digests.sum { |digest| Integer(digest.fetch(key)) }
      rescue ArgumentError, KeyError, TypeError
        raise ExecutionUnavailableError.new(
          "hub.mail.digest.invalid",
          "Prism Mail returned an invalid digest artifact"
        )
      end
    end
  end
end
