# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class SubprocessPorterGateway < Ports::PorterGateway
      REQUEST_SCHEMA_VERSION = "prism-porter.request.v1".freeze
      RESPONSE_SCHEMA_VERSION = Domain::DeliveryIntent::SCHEMA_VERSION
      DEFAULT_TIMEOUT_SECONDS = 10
      MAX_REQUEST_BYTES = 2 * 1024 * 1024
      MAX_STDOUT_BYTES = 4 * 1024 * 1024
      MAX_STDERR_BYTES = 65_536

      def initialize(command:, logger:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, runner_factory: nil)
        @command = command.freeze
        @logger = logger
        @timeout_seconds = timeout_seconds
        @runner_factory = runner_factory || method(:build_runner)
      end

      def build_delivery_intent(artifact:, routes:, chunk_max_chars: nil)
        normalized_artifact = normalize_artifact(artifact)
        normalized_routes = normalize_routes(routes)
        expected_context = route_context(normalized_artifact.fetch("artifact_kind"), normalized_routes)
        source = encode_request(
          artifact: normalized_artifact,
          routes: normalized_routes,
          chunk_max_chars: chunk_max_chars
        )
        reject_oversized_request!(source)

        runner = @runner_factory.call(
          command: @command,
          environment: {},
          timeout_seconds: @timeout_seconds,
          max_stdout_bytes: MAX_STDOUT_BYTES,
          max_stderr_bytes: MAX_STDERR_BYTES
        )
        result = runner.call(source)
        reject_process_failure!(result)
        intent = parse_intent(result.stdout)
        validate_expected!(intent, artifact: normalized_artifact, context: expected_context)
        intent
      rescue ProcessRunner::StartError => error
        raise ExecutionUnavailableError.new(
          "hub.porter.process.unavailable",
          "Prism Porter worker process could not be started",
          details: {"system_error" => error.system_error}
        )
      end

      private

      def build_runner(**options)
        ProcessRunner.new(**options)
      end

      def normalize_artifact(value)
        object = exact_object(value, %w[artifact_id artifact_kind payload], "artifact")
        kind = object.fetch("artifact_kind")
        id = object.fetch("artifact_id")
        valid = kind.is_a?(String) && kind.match?(Domain::DeliveryIntent::ARTIFACT_KIND_PATTERN) &&
          id.is_a?(String) && id.match?(Domain::DeliveryIntent::ARTIFACT_ID_PATTERN)
        raise_invalid_request("artifact identifiers are invalid") unless valid

        {
          "artifact_kind" => kind.dup.freeze,
          "artifact_id" => id.dup.freeze,
          "payload" => normalize_json_value(object.fetch("payload"))
        }.freeze
      end

      def normalize_routes(value)
        raise_invalid_request("routes must be a nonempty array") unless value.is_a?(Array) && !value.empty?

        seen = {}
        value.map do |entry|
          route = exact_object(entry, %w[artifact_kind logical_context], "route")
          kind = route.fetch("artifact_kind")
          unless kind.is_a?(String) && kind.match?(Domain::DeliveryIntent::ARTIFACT_KIND_PATTERN) && !seen[kind]
            raise_invalid_request("routes must have unique valid artifact kinds")
          end
          seen[kind] = true
          context = exact_object(route.fetch("logical_context"), %w[channel workspace], "logical_context")
          workspace = logical_identifier(context.fetch("workspace"), "workspace")
          channel = logical_identifier(context.fetch("channel"), "channel")
          {
            "artifact_kind" => kind.dup.freeze,
            "logical_context" => {"workspace" => workspace, "channel" => channel}.freeze
          }.freeze
        end.freeze
      end

      def route_context(kind, routes)
        route = routes.find { |candidate| candidate.fetch("artifact_kind") == kind }
        raise_invalid_request("artifact kind has no logical route") unless route

        route.fetch("logical_context")
      end

      def logical_identifier(value, field)
        valid = value.is_a?(String) && value.match?(/\A[^[:cntrl:]]{1,100}\z/) && !value.strip.empty?
        return value.strip.freeze if valid

        raise_invalid_request("#{field} must be a nonblank logical identifier")
      end

      def encode_request(artifact:, routes:, chunk_max_chars:)
        request = {
          "schema_version" => REQUEST_SCHEMA_VERSION,
          "artifact" => artifact,
          "routes" => routes
        }
        unless chunk_max_chars.nil?
          unless chunk_max_chars.is_a?(Integer) && (64..100_000).cover?(chunk_max_chars)
            raise_invalid_request("chunk_max_chars must be an integer from 64 to 100000")
          end
          request["chunk_max_chars"] = chunk_max_chars
        end
        JSON.generate(request)
      rescue JSON::GeneratorError
        raise_invalid_request("Porter request is not JSON-compatible")
      end

      def reject_oversized_request!(source)
        return if source.bytesize <= MAX_REQUEST_BYTES

        raise InputError.new(
          "hub.porter.request.too_large",
          "Prism Porter request exceeds the configured worker contract"
        )
      end

      def reject_process_failure!(result)
        if result.timed_out
          raise ExecutionUnavailableError.new(
            "hub.porter.process.timeout",
            "Prism Porter worker did not finish within the configured timeout"
          )
        end
        if result.stdout_too_large
          raise ExecutionUnavailableError.new(
            "hub.porter.response.too_large",
            "Prism Porter worker response exceeded the configured limit"
          )
        end
        if result.stderr_too_large
          raise ExecutionUnavailableError.new(
            "hub.porter.stderr.too_large",
            "Prism Porter worker diagnostics exceeded the configured limit"
          )
        end
        return if result.exit_status == 0

        @logger.warn("prism_porter_worker_failed exit_status=#{result.exit_status.inspect}")
        raise ExecutionUnavailableError.new(
          "hub.porter.process.failed",
          "Prism Porter worker exited without a valid delivery intent"
        )
      end

      def parse_intent(source)
        payload = JSON.parse(source)
        validate_response_shape!(payload)
        context = payload.fetch("logical_context")
        presentation = payload.fetch("presentation")
        Domain::DeliveryIntent.new(
          artifact_id: payload.fetch("artifact_id"),
          artifact_kind: payload.fetch("artifact_kind"),
          workspace: context.fetch("workspace"),
          channel: context.fetch("channel"),
          format: presentation.fetch("format"),
          chunks: payload.fetch("chunks"),
          idempotency_key: payload.fetch("idempotency_key")
        )
      rescue JSON::ParserError
        raise ExecutionUnavailableError.new(
          "hub.porter.response.invalid_json",
          "Prism Porter worker returned invalid JSON"
        )
      rescue KeyError, TypeError, InputError
        raise ExecutionUnavailableError.new(
          "hub.porter.response.invalid_intent",
          "Prism Porter worker response did not preserve the delivery intent contract"
        )
      end

      def validate_response_shape!(payload)
        valid = payload.is_a?(Hash) &&
          payload.keys.sort == %w[artifact_id artifact_kind chunks idempotency_key logical_context presentation schema_version] &&
          payload["schema_version"] == RESPONSE_SCHEMA_VERSION &&
          exact_keys?(payload["logical_context"], %w[channel workspace]) &&
          exact_keys?(payload["presentation"], %w[format])
        return if valid

        raise TypeError
      end

      def validate_expected!(intent, artifact:, context:)
        valid = intent.artifact_id == artifact.fetch("artifact_id") &&
          intent.artifact_kind == artifact.fetch("artifact_kind") &&
          intent.workspace == context.fetch("workspace") &&
          intent.channel == context.fetch("channel")
        return if valid

        raise ExecutionUnavailableError.new(
          "hub.porter.response.mismatch",
          "Prism Porter worker response does not match the requested artifact route"
        )
      end

      def exact_object(value, keys, label)
        unless exact_keys?(value, keys)
          raise_invalid_request("#{label} shape is invalid")
        end
        value
      end

      def exact_keys?(value, keys)
        value.is_a?(Hash) && value.keys.all?(String) && value.keys.sort == keys.sort
      end

      def normalize_json_value(value)
        return value.each_with_object({}) do |(key, item), result|
          raise_invalid_request("artifact payload keys must be nonblank strings") unless key.is_a?(String) && !key.empty?
          result[key.dup.freeze] = normalize_json_value(item)
        end.freeze if value.is_a?(Hash)
        return value.map { |item| normalize_json_value(item) }.freeze if value.is_a?(Array)
        return value.dup.freeze if value.is_a?(String) && value.valid_encoding?
        return value if value.is_a?(Numeric) || value.equal?(true) || value.equal?(false) || value.nil?

        raise_invalid_request("artifact payload contains a non-JSON value")
      end

      def raise_invalid_request(message)
        raise InputError.new("hub.porter.request.invalid", message)
      end
    end
  end
end
