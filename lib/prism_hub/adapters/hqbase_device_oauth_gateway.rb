# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class HqbaseDeviceOauthGateway < Ports::MailOauthGateway
      DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code".freeze
      SCOPES = %w[mail:read offline_access].freeze
      CLIENT_NAME = "Prism Hub".freeze
      MAX_RESPONSE_BYTES = 512 * 1024
      CONNECT_TIMEOUT = 5
      READ_TIMEOUT = 15
      WRITE_TIMEOUT = 5

      Start = Data.define(
        :client_id,
        :device_code,
        :user_code,
        :verification_uri,
        :verification_uri_complete,
        :expires_in,
        :interval
      )
      Poll = Data.define(:status, :access_token, :refresh_token, :scope, :token_type, :expires_in, :error)

      def initialize(origin:, transport: nil)
        @origin = normalized_origin(origin)
        @resource = "#{@origin}/api/v1".freeze
        @transport = transport || method(:request)
      end

      attr_reader :origin, :resource

      def start
        client_id = register_client
        response = form_post(
          "/api/auth/device/code",
          "client_id" => client_id,
          "resource" => resource,
          "scope" => SCOPES.join(" ")
        )
        payload = success_json(response, "device authorization")

        Start.new(
          client_id: client_id,
          device_code: required_string(payload, "device_code"),
          user_code: required_string(payload, "user_code"),
          verification_uri: required_https_url(payload, "verification_uri"),
          verification_uri_complete: required_https_url(payload, "verification_uri_complete"),
          expires_in: positive_integer(payload, "expires_in"),
          interval: positive_integer(payload, "interval")
        )
      end

      def poll(client_id:, device_code:)
        response = form_post(
          "/api/auth/oauth2/token",
          "client_id" => String(client_id),
          "device_code" => String(device_code),
          "grant_type" => DEVICE_GRANT,
          "resource" => resource
        )
        payload = json(response)

        if response.status == 200
          return Poll.new(
            status: :connected,
            access_token: required_string(payload, "access_token"),
            refresh_token: optional_string(payload, "refresh_token"),
            scope: required_string(payload, "scope").split,
            token_type: required_string(payload, "token_type"),
            expires_in: positive_integer(payload, "expires_in"),
            error: nil
          )
        end

        error = payload["error"]
        status = case error
        when "authorization_pending", "slow_down" then :pending
        when "access_denied" then :denied
        when "expired_token" then :expired
        else :failed
        end
        Poll.new(
          status: status,
          access_token: nil,
          refresh_token: nil,
          scope: [],
          token_type: nil,
          expires_in: nil,
          error: String(error || "oauth_error")
        )
      end

      private

      Response = Data.define(:status, :body)

      def register_client
        response = json_post(
          "/api/auth/oauth2/register",
          {
            "application_type" => "native",
            "client_name" => CLIENT_NAME,
            "grant_types" => [DEVICE_GRANT, "refresh_token"],
            "resources" => [resource],
            "scope" => SCOPES.join(" "),
            "token_endpoint_auth_method" => "none"
          }
        )
        required_string(success_json(response, "client registration"), "client_id")
      end

      def json_post(path, payload)
        perform(
          path,
          headers: {"content-type" => "application/json"},
          body: JSON.generate(payload)
        )
      end

      def form_post(path, payload)
        perform(
          path,
          headers: {"content-type" => "application/x-www-form-urlencoded"},
          body: URI.encode_www_form(payload)
        )
      end

      def perform(path, headers:, body:)
        uri = URI.parse("#{origin}#{path}")
        response = @transport.call(uri: uri, headers: headers, body: body)
        Response.new(status: Integer(response.fetch(:status)), body: String(response.fetch(:body)))
      rescue KeyError, ArgumentError, URI::InvalidURIError => error
        raise ExecutionUnavailableError.new(
          "hub.mail.oauth.transport_invalid",
          "HQBase OAuth transport returned an invalid response",
          details: {"cause" => error.class.name}
        )
      end

      def request(uri:, headers:, body:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = CONNECT_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.write_timeout = WRITE_TIMEOUT
        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = body
        response = http.request(request)
        response_body = response.body.to_s
        if response_body.bytesize > MAX_RESPONSE_BYTES
          raise ExecutionUnavailableError.new(
            "hub.mail.oauth.response_too_large",
            "HQBase OAuth response exceeded the configured limit"
          )
        end
        {status: response.code.to_i, body: response_body}
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
        raise ExecutionUnavailableError.new(
          "hub.mail.oauth.unavailable",
          "HQBase OAuth endpoint is unavailable",
          details: {"cause" => error.class.name}
        )
      end

      def success_json(response, operation)
        return json(response) if response.status.between?(200, 299)

        raise ExecutionUnavailableError.new(
          "hub.mail.oauth.rejected",
          "HQBase OAuth #{operation} was rejected",
          details: {"status" => response.status}
        )
      end

      def json(response)
        payload = JSON.parse(response.body)
        return payload if payload.is_a?(Hash)

        raise JSON::ParserError, "expected object"
      rescue JSON::ParserError
        raise ExecutionUnavailableError.new(
          "hub.mail.oauth.invalid_json",
          "HQBase OAuth returned invalid JSON"
        )
      end

      def required_string(payload, key)
        value = payload[key]
        return value if value.is_a?(String) && !value.empty?

        invalid_payload!(key)
      end

      def optional_string(payload, key)
        value = payload[key]
        return if value.nil?
        return value if value.is_a?(String) && !value.empty?

        invalid_payload!(key)
      end

      def positive_integer(payload, key)
        value = payload[key]
        return value if value.is_a?(Integer) && value.positive?

        invalid_payload!(key)
      end

      def required_https_url(payload, key)
        value = required_string(payload, key)
        uri = URI.parse(value)
        return value if uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo

        invalid_payload!(key)
      rescue URI::InvalidURIError
        invalid_payload!(key)
      end

      def invalid_payload!(field)
        raise ExecutionUnavailableError.new(
          "hub.mail.oauth.invalid_payload",
          "HQBase OAuth response is missing a required field",
          details: {"field" => field}
        )
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
