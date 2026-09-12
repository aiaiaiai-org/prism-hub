# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class HqbaseMailboxGateway < Ports::MailboxGateway
      MAX_RESPONSE_BYTES = 1024 * 1024
      CONNECT_TIMEOUT = 5
      READ_TIMEOUT = 15

      Response = Data.define(:status, :body)

      def initialize(origin:, transport: nil)
        @origin = normalized_origin(origin)
        @transport = transport || method(:request)
      end

      def list(access_token:)
        token = String(access_token)
        raise ArgumentError if token.empty?

        uri = URI.parse("#{@origin}/api/v1/mailboxes")
        raw = @transport.call(
          uri: uri,
          headers: {"authorization" => "Bearer #{token}", "accept" => "application/json"}
        )
        response = Response.new(status: Integer(raw.fetch(:status)), body: String(raw.fetch(:body)))
        parse_response(response)
      rescue KeyError, ArgumentError, URI::InvalidURIError => error
        raise ExecutionUnavailableError.new(
          "hub.mail.mailboxes.transport_invalid",
          "HQBase mailbox transport returned an invalid response",
          details: {"cause" => error.class.name}
        )
      end

      private

      def request(uri:, headers:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = CONNECT_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        response = http.request(Net::HTTP::Get.new(uri.request_uri, headers))
        body = response.body.to_s
        if body.bytesize > MAX_RESPONSE_BYTES
          raise ExecutionUnavailableError.new(
            "hub.mail.mailboxes.response_too_large",
            "HQBase mailbox response exceeded the configured limit"
          )
        end

        {status: response.code.to_i, body: body}
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
        raise ExecutionUnavailableError.new(
          "hub.mail.mailboxes.unavailable",
          "HQBase mailbox endpoint is unavailable",
          details: {"cause" => error.class.name}
        )
      end

      def parse_response(response)
        case response.status
        when 200
          parse_mailboxes(response.body)
        when 401, 403
          raise AuthorisationError.new(
            "hub.mail.mailboxes.access_denied",
            "HQBase rejected mailbox discovery authorization"
          )
        when 429
          raise ExecutionUnavailableError.new(
            "hub.mail.mailboxes.rate_limited",
            "HQBase mailbox discovery was rate limited"
          )
        else
          raise ExecutionUnavailableError.new(
            "hub.mail.mailboxes.rejected",
            "HQBase mailbox discovery failed",
            details: {"status" => response.status}
          )
        end
      end

      def parse_mailboxes(body)
        payload = JSON.parse(body)
        raise JSON::ParserError, "expected array" unless payload.is_a?(Array)

        payload.map { |mailbox| mailbox_value(mailbox) }.freeze
      rescue JSON::ParserError
        raise ExecutionUnavailableError.new(
          "hub.mail.mailboxes.invalid_json",
          "HQBase mailbox discovery returned invalid JSON"
        )
      end

      def mailbox_value(payload)
        raise JSON::ParserError, "expected object" unless payload.is_a?(Hash)

        Domain::Mailbox.new(
          id: required_string(payload, "id"),
          address: required_string(payload, "address"),
          display_name: required_string(payload, "displayName"),
          is_active: required_boolean(payload, "isActive"),
          access_level: required_string(payload, "accessLevel")
        )
      rescue InputError => error
        raise ExecutionUnavailableError.new(
          "hub.mail.mailboxes.invalid_payload",
          "HQBase mailbox discovery returned an invalid mailbox",
          details: {"cause" => error.code}
        )
      end

      def required_string(payload, key)
        value = payload[key]
        return value if value.is_a?(String) && !value.empty?

        raise JSON::ParserError, "missing #{key}"
      end

      def required_boolean(payload, key)
        value = payload[key]
        return value if value == true || value == false

        raise JSON::ParserError, "missing #{key}"
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
          "hub.mail.hqbase_origin.invalid",
          "HQBASE_ORIGIN must be an HTTPS origin without path, credentials, query, or fragment"
        )
      end
    end
  end
end
