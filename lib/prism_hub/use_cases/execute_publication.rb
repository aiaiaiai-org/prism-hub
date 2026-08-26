# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module UseCases
    class ExecutePublication
      OPERATIONS = %w[publish validate].freeze
      IDEMPOTENCY_PATTERN = /\A[!-~]{1,256}\z/

      def initialize(operation:, channel_repository:, execution_gateway:, request_id_factory:)
        unless OPERATIONS.include?(operation)
          raise ArgumentError, "unsupported Prism execution operation"
        end

        @operation = operation.freeze
        @channel_repository = channel_repository
        @execution_gateway = execution_gateway
        @request_id_factory = request_id_factory
      end

      def call(draft:, idempotency_key:)
        normalized_key = normalize_idempotency_key(idempotency_key)
        channels = draft.targets.to_h do |target|
          [target.channel_id, @channel_repository.find(target.channel_id)]
        end
        request_id = @request_id_factory.call
        envelope = {
          "protocol_version" => "prism-execution.v1",
          "request_id" => request_id,
          "operation" => @operation,
          "payload" => draft.prism_payload(
            idempotency_key: normalized_key,
            channels: channels
          )
        }
        @execution_gateway.execute(envelope)
      end

      private

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
