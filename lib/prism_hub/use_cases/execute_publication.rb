# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ExecutePublication
      OPERATIONS = %w[publish validate].freeze
      OPERATION_CAPABILITIES = {
        "publish" => Domain::Capabilities::PUBLICATIONS_PUBLISH,
        "validate" => Domain::Capabilities::PUBLICATIONS_VALIDATE
      }.freeze
      IDEMPOTENCY_PATTERN = /\A[!-~]{1,256}\z/

      def initialize(operation:, channel_repository:, execution_gateway:)
        unless OPERATIONS.include?(operation)
          raise ArgumentError, "unsupported Prism execution operation"
        end

        @operation = operation.freeze
        @channel_repository = channel_repository
        @execution_gateway = execution_gateway
      end

      def call(draft:, idempotency_key:, request_id:, authorisation_context:)
        target_channel_ids = draft.targets.map(&:channel_id).uniq
        authorise!(authorisation_context, target_channel_ids)

        normalized_key = normalize_idempotency_key(idempotency_key)
        normalized_request_id = normalize_request_id(request_id)
        channels = draft.targets.to_h do |target|
          [target.channel_id, @channel_repository.find(target.channel_id)]
        end
        envelope = {
          "protocol_version" => "prism-execution.v1",
          "request_id" => normalized_request_id,
          "operation" => @operation,
          "payload" => draft.prism_payload(
            idempotency_key: normalized_key,
            channels: channels
          )
        }
        @execution_gateway.execute(envelope)
      end

      private

      def authorise!(authorisation_context, channel_ids)
        required_capability = OPERATION_CAPABILITIES.fetch(@operation)
        unless authorisation_context.allows_capability?(required_capability)
          raise AuthorisationError.new(
            "hub.authorization.capability_denied",
            "the authenticated principal cannot #{@operation} publications"
          )
        end

        denied = channel_ids.reject { |channel_id| authorisation_context.allows_channel?(channel_id) }
        return if denied.empty?

        raise AuthorisationError.new(
          "hub.authorization.channel_denied",
          "the publication targets channels outside the authenticated principal scope",
          details: {"channel_ids" => denied.sort}
        )
      end

      def normalize_request_id(value)
        string = String(value)
        return string.freeze if Domain::Channel::REFERENCE_PATTERN.match?(string)

        raise InputError.new(
          "hub.request_id.invalid",
          "request id must be a non-empty stable reference"
        )
      end

      def normalize_idempotency_key(value)
        string = String(value)
        return string.freeze if IDEMPOTENCY_PATTERN.match?(string)

        raise InputError.new(
          "hub.idempotency_key.invalid",
          "Idempotency-Key must contain 1 to 256 visible ASCII characters"
        )
      end
    end
  end
end
