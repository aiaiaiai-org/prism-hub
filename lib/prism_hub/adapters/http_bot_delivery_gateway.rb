# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class HttpBotDeliveryGateway < Ports::BotDeliveryGateway
      CONNECT_TIMEOUT = 5
      READ_TIMEOUT = 15
      MAX_RESPONSE_BYTES = 64 * 1024
      DELIVERY_PATH = "/api/v1/delivery".freeze

      Response = Data.define(:status, :body)

      def initialize(origin:, secret:, transport: nil)
        @origin = normalized_origin(origin)
        @secret = required_secret(secret)
        @transport = transport || method(:request)
      end

      def deliver(intent:, binding:)
        validate_inputs!(intent, binding)
        results = intent.chunks.map do |chunk|
          deliver_chunk(intent: intent, binding: binding, chunk: chunk)
        end
        results.freeze
      end

      private

      def deliver_chunk(intent:, binding:, chunk:)
        idempotency_key = Digest::SHA256.hexdigest(
          [intent.idempotency_key, chunk.position].join("\0")
        )
        uri = URI.parse("#{@origin}#{DELIVERY_PATH}")
        raw = @transport.call(
          uri: uri,
          headers: {
            "content-type" => "application/json",
            "accept" => "application/json",
            "x-prism-bot-delivery-secret" => @secret
          },
          body: JSON.generate(
            "chat_id" => binding.chat_id,
            "message_thread_id" => binding.message_thread_id,
            "text" => chunk.text,
            "idempotency_key" => idempotency_key
          )
        )
        response = Response.new(status: Integer(raw.fetch(:status)), body: String(raw.fetch(:body)))
        parse_response(response, idempotency_key: idempotency_key)
      rescue KeyError, ArgumentError, TypeError, URI::InvalidURIError => error
        raise ExecutionUnavailableError.new(
          "hub.bot.delivery.transport_invalid",
          "Prism Bot delivery transport returned an invalid response",
          details: {"cause" => error.class.name}
        )
      end

      def parse_response(response, idempotency_key:)
        payload = parse_json(response.body)
        case response.status
        when 200
          validate_success(payload, idempotency_key)
        when 429
          raise ExecutionUnavailableError.new(
            "hub.bot.delivery.rate_limited",
            "Prism Bot delivery was rate limited",
            details: {"retry_after_seconds" => payload.dig("error", "retry_after_seconds")}
          )
        when 401, 403
          raise ExecutionUnavailableError.new(
            "hub.bot.delivery.access_denied",
            "Prism Bot rejected the delivery authorization"
          )
        when 400, 413, 415
          raise InputError.new(
            "hub.bot.delivery.request_rejected",
            "Prism Bot rejected the delivery request",
            details: {"code" => payload.dig("error", "code")}
          )
        else
          raise ExecutionUnavailableError.new(
            "hub.bot.delivery.rejected",
            "Prism Bot delivery failed",
            details: {"status" => response.status, "code" => payload.dig("error", "code")}
          )
        end
      end

      def validate_success(payload, idempotency_key)
        valid = payload.is_a?(Hash) && payload["status"] == "ok" &&
          payload.dig("delivery", "idempotency_key") == idempotency_key &&
          payload.dig("delivery", "provider_message_id")
        return payload["delivery"].freeze if valid

        raise ExecutionUnavailableError.new(
          "hub.bot.delivery.invalid_response",
          "Prism Bot returned an invalid delivery response"
        )
      end

      def parse_json(body)
        JSON.parse(body)
      rescue JSON::ParserError
        raise ExecutionUnavailableError.new(
          "hub.bot.delivery.invalid_json",
          "Prism Bot returned invalid JSON"
        )
      end

      def request(uri:, headers:, body:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = CONNECT_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        response = http.request(Net::HTTP::Post.new(uri.request_uri, headers).tap { |request| request.body = body })
        response_body = response.body.to_s
        if response_body.bytesize > MAX_RESPONSE_BYTES
          raise ExecutionUnavailableError.new(
            "hub.bot.delivery.response_too_large",
            "Prism Bot delivery response exceeded the configured limit"
          )
        end
        {status: response.code.to_i, body: response_body}
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
        raise ExecutionUnavailableError.new(
          "hub.bot.delivery.unavailable",
          "Prism Bot delivery endpoint is unavailable",
          details: {"cause" => error.class.name}
        )
      end

      def validate_inputs!(intent, binding)
        unless intent.is_a?(Domain::DeliveryIntent) && binding.is_a?(Domain::TelegramSurfaceBinding) && binding.active?
          raise InputError.new(
            "hub.bot.delivery.inputs.invalid",
            "Bot delivery requires a DeliveryIntent and an active Telegram surface binding"
          )
        end
        unless intent.workspace == binding.workspace_id && intent.channel == binding.logical_channel
          raise InputError.new(
            "hub.bot.delivery.context.mismatch",
            "Delivery intent does not match the Telegram surface binding"
          )
        end
      end

      def normalized_origin(value)
        uri = URI.parse(String(value))
        valid_path = uri.path.nil? || uri.path.empty? || uri.path == "/"
        unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && valid_path
          raise ArgumentError
        end
        "https://#{uri.host}#{uri.port == 443 ? "" : ":#{uri.port}"}"
      rescue URI::InvalidURIError, ArgumentError
        raise ConfigurationError.new(
          "hub.bot.origin.invalid",
          "PRISM_BOT_ORIGIN must be an HTTPS origin without path, credentials, query, or fragment"
        )
      end

      def required_secret(value)
        secret = String(value)
        return secret.freeze unless secret.empty?
        raise ConfigurationError.new("hub.bot.delivery_secret.missing", "PRISM_BOT_DELIVERY_SECRET must not be empty")
      rescue TypeError
        raise ConfigurationError.new("hub.bot.delivery_secret.missing", "PRISM_BOT_DELIVERY_SECRET must be configured")
      end
    end
  end
end
