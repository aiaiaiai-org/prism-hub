# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    # What the outbox holds until a delivery target is known.
    #
    # Chunking is a per-target decision: the number of characters a message may
    # carry belongs to the surface that receives it, and a surface is resolved at
    # dispatch. So the queue stores the artifact and its routes, and Porter runs
    # once the bound can be computed from real targets.
    class DeliveryRequest
      SCHEMA_VERSION = "prism-hub.delivery-request.v1".freeze
      IDEMPOTENCY_KEY_PATTERN = /\A[0-9a-f]{64}\z/
      ARTIFACT_KEYS = %w[artifact_id artifact_kind payload].freeze

      attr_reader :artifact, :routes, :workspace, :channel, :idempotency_key, :chunk_max_chars_limit

      def self.from_h(value)
        unless value.is_a?(Hash) && value["schema_version"] == SCHEMA_VERSION
          raise InputError.new(
            "hub.delivery_request.schema.invalid",
            "delivery request must carry #{SCHEMA_VERSION}"
          )
        end

        new(
          artifact: value.fetch("artifact"),
          routes: value.fetch("routes"),
          workspace: value.fetch("workspace"),
          channel: value.fetch("channel"),
          idempotency_key: value.fetch("idempotency_key"),
          chunk_max_chars_limit: value["chunk_max_chars_limit"]
        )
      rescue KeyError
        raise InputError.new(
          "hub.delivery_request.invalid",
          "delivery request is missing required fields"
        )
      end

      def initialize(artifact:, routes:, workspace:, channel:, idempotency_key:, chunk_max_chars_limit: nil)
        @artifact = artifact_value(artifact)
        @routes = routes_value(routes)
        @workspace = logical_identifier(workspace, "workspace")
        @channel = logical_identifier(channel, "channel")
        @idempotency_key = idempotency_key_value(idempotency_key)
        @chunk_max_chars_limit = optional_limit(chunk_max_chars_limit)
        freeze
      end

      def to_h
        {
          "schema_version" => SCHEMA_VERSION,
          "artifact" => artifact,
          "routes" => routes,
          "workspace" => workspace,
          "channel" => channel,
          "idempotency_key" => idempotency_key,
          "chunk_max_chars_limit" => chunk_max_chars_limit
        }.freeze
      end

      private

      def artifact_value(value)
        unless value.is_a?(Hash) && (ARTIFACT_KEYS - value.keys).empty?
          raise InputError.new(
            "hub.delivery_request.artifact.invalid",
            "delivery request artifact must carry #{ARTIFACT_KEYS.join(", ")}"
          )
        end

        deep_copy(value, "artifact")
      end

      def routes_value(value)
        unless value.is_a?(Array) && !value.empty? && value.all?(Hash)
          raise InputError.new(
            "hub.delivery_request.routes.invalid",
            "delivery request routes must be a nonempty array of objects"
          )
        end

        deep_copy(value, "routes")
      end

      def logical_identifier(value, field)
        valid = value.is_a?(String) && value.match?(/\A[^[:cntrl:]]{1,100}\z/) && !value.strip.empty?
        return value.strip.freeze if valid

        raise InputError.new(
          "hub.delivery_request.#{field}.invalid",
          "#{field} must be a nonblank logical identifier"
        )
      end

      def idempotency_key_value(value)
        return value.dup.freeze if value.is_a?(String) && value.match?(IDEMPOTENCY_KEY_PATTERN)

        raise InputError.new(
          "hub.delivery_request.idempotency_key.invalid",
          "delivery request idempotency key is invalid"
        )
      end

      def optional_limit(value)
        return nil if value.nil?
        return value if value.is_a?(Integer) && DeliveryTextBound::SUPPORTED_RANGE.cover?(value)

        raise InputError.new(
          "hub.delivery_request.chunk_max_chars_limit.invalid",
          "chunk_max_chars_limit must be an integer within #{DeliveryTextBound::SUPPORTED_RANGE}"
        )
      end

      def deep_copy(value, field)
        DeepFreeze.call(Marshal.load(Marshal.dump(value)))
      rescue TypeError
        raise InputError.new(
          "hub.delivery_request.#{field}.invalid",
          "delivery request #{field} is not serializable"
        )
      end
    end
  end
end
