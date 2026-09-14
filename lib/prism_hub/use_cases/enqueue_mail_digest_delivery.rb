# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module UseCases
    class EnqueueMailDigestDelivery
      ARTIFACT_KIND = "mail.digest".freeze

      def initialize(generate_mail_digest:, generate_mail_digests:, outbox_repository:, clock: -> { Time.now.utc })
        @generate_mail_digest = generate_mail_digest
        @generate_mail_digests = generate_mail_digests
        @outbox_repository = outbox_repository
        @clock = clock
      end

      # chunk_max_chars is an operator ceiling, not the split itself. The split is
      # computed at dispatch from the targets that will receive the message, and
      # this value can only lower that result.
      def call(since:, before:, workspace:, channel:, mailbox_id: nil, chunk_max_chars: nil)
        artifact = generate_artifact(since: since, before: before, mailbox_id: mailbox_id)
        reference = artifact_id(artifact)
        request = Domain::DeliveryRequest.new(
          artifact: {
            "artifact_id" => reference,
            "artifact_kind" => ARTIFACT_KIND,
            "payload" => artifact
          },
          routes: [
            {
              "artifact_kind" => ARTIFACT_KIND,
              "logical_context" => {"workspace" => workspace, "channel" => channel}
            }
          ],
          workspace: workspace,
          channel: channel,
          idempotency_key: Digest::SHA256.hexdigest(reference),
          chunk_max_chars_limit: chunk_max_chars
        )
        @outbox_repository.enqueue(request: request, available_at: @clock.call.utc)
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
