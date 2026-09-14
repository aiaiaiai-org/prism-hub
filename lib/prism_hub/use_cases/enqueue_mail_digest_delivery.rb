# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class EnqueueMailDigestDelivery
      ARTIFACT_KIND = "mail.digest".freeze

      def initialize(generate_mail_digest:, generate_mail_digests:, build_delivery_intent:, outbox_repository:, clock: -> { Time.now.utc })
        @generate_mail_digest = generate_mail_digest
        @generate_mail_digests = generate_mail_digests
        @build_delivery_intent = build_delivery_intent
        @outbox_repository = outbox_repository
        @clock = clock
      end

      def call(since:, before:, workspace:, channel:, mailbox_id: nil, chunk_max_chars: nil)
        artifact = generate_artifact(since: since, before: before, mailbox_id: mailbox_id)
        intent = @build_delivery_intent.call(
          artifact: {
            "artifact_id" => artifact_id(artifact),
            "artifact_kind" => ARTIFACT_KIND,
            "payload" => artifact
          },
          routes: [
            {
              "artifact_kind" => ARTIFACT_KIND,
              "logical_context" => {"workspace" => workspace, "channel" => channel}
            }
          ],
          chunk_max_chars: chunk_max_chars
        )
        @outbox_repository.enqueue(intent: intent, available_at: @clock.call.utc)
      end

      private

      def generate_artifact(since:, before:, mailbox_id:)
        if mailbox_id.nil? || mailbox_id.empty?
          @generate_mail_digests.call(since: since, before: before)
        else
          @generate_mail_digest.call(mailbox_id: mailbox_id, since: since, before: before)
        end
      end

      def artifact_id(artifact)
        "mail-digest-#{Digest::SHA256.hexdigest(JSON.generate(artifact))}"
      rescue JSON::GeneratorError
        raise InputError.new(
          "hub.mail.digest.artifact.invalid",
          "mail digest artifact is not JSON-compatible"
        )
      end
    end
  end
end
