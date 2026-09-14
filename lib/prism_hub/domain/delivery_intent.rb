# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    class DeliveryIntent
      SCHEMA_VERSION = "prism-porter.delivery-intent.v1".freeze
      FORMAT = "plain_text".freeze
      ARTIFACT_KIND_PATTERN = /\A[a-z0-9]+(?:[._-][a-z0-9]+)*\z/
      ARTIFACT_ID_PATTERN = /\A[^[:cntrl:]\s]{1,200}\z/
      IDEMPOTENCY_KEY_PATTERN = /\A[0-9a-f]{64}\z/

      Chunk = Data.define(:text, :position, :total) do
        def to_h
          {"text" => text, "position" => position, "total" => total}.freeze
        end
      end

      attr_reader :artifact_id, :artifact_kind, :workspace, :channel, :format, :chunks, :idempotency_key

      def self.from_h(value)
        unless value.is_a?(Hash) && value["schema_version"] == SCHEMA_VERSION
          raise InputError.new(
            "hub.porter.delivery_intent.payload.invalid",
            "delivery intent payload schema is unsupported"
          )
        end

        context = value.fetch("logical_context")
        presentation = value.fetch("presentation")
        chunks = value.fetch("chunks")
        unless context.is_a?(Hash) && presentation.is_a?(Hash) && chunks.is_a?(Array)
          raise InputError.new(
            "hub.porter.delivery_intent.payload.invalid",
            "delivery intent payload shape is invalid"
          )
        end

        new(
          artifact_id: value.fetch("artifact_id"),
          artifact_kind: value.fetch("artifact_kind"),
          workspace: context.fetch("workspace"),
          channel: context.fetch("channel"),
          format: presentation.fetch("format"),
          chunks: chunks,
          idempotency_key: value.fetch("idempotency_key")
        )
      rescue KeyError, TypeError
        raise InputError.new(
          "hub.porter.delivery_intent.payload.invalid",
          "delivery intent payload is incomplete"
        )
      end

      def initialize(artifact_id:, artifact_kind:, workspace:, channel:, format:, chunks:, idempotency_key:)
        @artifact_id = identifier(artifact_id, "artifact_id", ARTIFACT_ID_PATTERN)
        @artifact_kind = identifier(artifact_kind, "artifact_kind", ARTIFACT_KIND_PATTERN)
        @workspace = logical_identifier(workspace, "workspace")
        @channel = logical_identifier(channel, "channel")
        @format = presentation_format(format)
        @chunks = chunk_collection(chunks)
        @idempotency_key = idempotency_key_value(idempotency_key)
        validate_fingerprint!
        freeze
      end

      def text
        chunks.map(&:text).join.freeze
      end

      def to_h
        {
          "schema_version" => SCHEMA_VERSION,
          "artifact_id" => artifact_id,
          "artifact_kind" => artifact_kind,
          "logical_context" => {"workspace" => workspace, "channel" => channel}.freeze,
          "presentation" => {"format" => format}.freeze,
          "chunks" => chunks.map(&:to_h).freeze,
          "idempotency_key" => idempotency_key
        }.freeze
      end

      private

      def identifier(value, field, pattern)
        return value.dup.freeze if value.is_a?(String) && value.match?(pattern)

        raise InputError.new(
          "hub.porter.delivery_intent.#{field}.invalid",
          "#{field} is invalid"
        )
      end

      def logical_identifier(value, field)
        valid = value.is_a?(String) && value.match?(/\A[^[:cntrl:]]{1,100}\z/) && !value.strip.empty?
        return value.strip.freeze if valid

        raise InputError.new(
          "hub.porter.delivery_intent.#{field}.invalid",
          "#{field} must be a nonblank logical identifier"
        )
      end

      def presentation_format(value)
        return FORMAT if value == FORMAT

        raise InputError.new(
          "hub.porter.delivery_intent.format.invalid",
          "delivery intent presentation format is unsupported"
        )
      end

      def chunk_collection(value)
        unless value.is_a?(Array) && !value.empty?
          raise InputError.new(
            "hub.porter.delivery_intent.chunks.invalid",
            "delivery intent requires presentation chunks"
          )
        end

        total = value.length
        normalized = value.each_with_index.map do |chunk, index|
          normalize_chunk(chunk, position: index + 1, total: total)
        end
        normalized.freeze
      end

      def normalize_chunk(value, position:, total:)
        unless value.is_a?(Hash) && value.keys.sort == %w[position text total]
          raise InputError.new(
            "hub.porter.delivery_intent.chunk.invalid",
            "delivery intent chunk shape is invalid"
          )
        end

        text = value.fetch("text")
        actual_position = value.fetch("position")
        actual_total = value.fetch("total")
        valid = text.is_a?(String) && text.valid_encoding? && !text.empty? &&
          actual_position == position && actual_total == total
        unless valid
          raise InputError.new(
            "hub.porter.delivery_intent.chunk.invalid",
            "delivery intent chunks must be nonempty and sequential"
          )
        end

        Chunk.new(text: text.dup.freeze, position: actual_position, total: actual_total).freeze
      end

      def idempotency_key_value(value)
        return value.dup.freeze if value.is_a?(String) && IDEMPOTENCY_KEY_PATTERN.match?(value)

        raise InputError.new(
          "hub.porter.delivery_intent.idempotency_key.invalid",
          "delivery intent idempotency key is invalid"
        )
      end

      def validate_fingerprint!
        expected = Digest::SHA256.hexdigest([
          artifact_kind,
          artifact_id,
          workspace,
          channel,
          format,
          text
        ].join("\0"))
        return if idempotency_key == expected

        raise InputError.new(
          "hub.porter.delivery_intent.idempotency_key.mismatch",
          "delivery intent idempotency key does not match its contents"
        )
      end
    end
  end
end
