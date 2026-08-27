# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  class Bootstrap
    class << self
      def build(env:, logger: Logger.new($stdout), clock: -> { Time.now.utc })
        channels = Adapters::EnvironmentChannelRepository.new(
          env.fetch("PRISM_HUB_CHANNELS_JSON", "[]")
        )
        gateway = build_gateway(env, logger)
        request_ids = Adapters::SecureRequestIdFactory.new
        request_body = Interfaces::Http::RequestBody.new(
          max_bytes: integer(env.fetch("PRISM_HUB_MAX_BODY_BYTES", "1048576"), "body limit")
        )

        list_channels = UseCases::ListChannels.new(channel_repository: channels)
        resolve_actor = UseCases::ResolveWorkspaceActor.new(
          binding_repository: Adapters::ActiveRecordProviderIdentityBindingRepository.new,
          workspace_membership_repository: Adapters::ActiveRecordWorkspaceMembershipRepository.new
        )
        validate = execution_use_case(
          "validate",
          channels: channels,
          gateway: gateway
        )
        publish = execution_use_case(
          "publish",
          channels: channels,
          gateway: gateway
        )
        credential_repository = Adapters::ActiveRecordClientCredentialRepository.new
        authenticator = Interfaces::Http::Authenticator.new(
          credential_repository: credential_repository,
          clock: clock,
          **legacy_authentication(env, channels)
        )

        Interfaces::Http::App.new(
          authenticator: authenticator,
          health_endpoint: Interfaces::Http::HealthEndpoint.new,
          routes: {
            ["POST", "/api/v1/actors/resolve"] => Interfaces::Http::ActorResolutionEndpoint.new(
              resolve_workspace_actor: resolve_actor,
              request_body: request_body
            ),
            ["GET", "/api/v1/channels"] => Interfaces::Http::ChannelsEndpoint.new(
              list_channels: list_channels,
              cursor: Interfaces::Http::ChannelCursor.new
            ),
            ["POST", "/api/v1/publications/validate"] => Interfaces::Http::PublicationEndpoint.new(
              execute_publication: validate,
              request_body: request_body
            ),
            ["POST", "/api/v1/publications"] => Interfaces::Http::PublicationEndpoint.new(
              execute_publication: publish,
              request_body: request_body
            )
          },
          logger: logger,
          request_id_factory: request_ids
        )
      rescue KeyError => error
        raise ConfigurationError.new(
          "hub.configuration.missing",
          "required environment value is missing: #{error.key}"
        )
      end

      private

      def legacy_authentication(env, channels)
        enabled = boolean(
          env.fetch("PRISM_HUB_LEGACY_TOKEN_ENABLED", "false"),
          "legacy token flag"
        )
        return {} unless enabled

        {
          legacy_token: env.fetch("PRISM_HUB_API_TOKEN"),
          legacy_context: Domain::AuthorisationContext.new(
            principal_id: "legacy-global",
            workspace_id: "legacy-global",
            capabilities: Domain::Capabilities::ALL,
            allowed_channel_ids: channels.all_ids
          )
        }
      end

      def build_gateway(env, logger)
        runner = Adapters::ProcessRunner.new(
          command: command(env.fetch("PRISM_RUNTIME_COMMAND_JSON", '["prism-runtime","--json"]')),
          environment: {"RUST_LOG" => env.fetch("PRISM_RUNTIME_LOG", "warn")},
          timeout_seconds: number(
            env.fetch("PRISM_RUNTIME_TIMEOUT_SECONDS", "10"),
            "runtime timeout"
          )
        )
        Adapters::SubprocessExecutionGateway.new(runner: runner, logger: logger)
      end

      def execution_use_case(operation, channels:, gateway:)
        UseCases::ExecutePublication.new(
          operation: operation,
          channel_repository: channels,
          execution_gateway: gateway
        )
      end

      def command(source)
        value = JSON.parse(source)
        if value.is_a?(Array) && value.any? && value.all? { |part| part.is_a?(String) && !part.empty? }
          return value.freeze
        end

        raise ConfigurationError.new(
          "hub.prism.command.invalid",
          "PRISM_RUNTIME_COMMAND_JSON must be a non-empty JSON string array"
        )
      rescue JSON::ParserError
        raise ConfigurationError.new(
          "hub.prism.command.invalid_json",
          "PRISM_RUNTIME_COMMAND_JSON must contain valid JSON"
        )
      end

      def boolean(source, label)
        return true if source == "true"
        return false if source == "false"

        raise ConfigurationError.new(
          "hub.configuration.invalid_boolean",
          "#{label} must be true or false"
        )
      end

      def integer(source, label)
        value = Integer(source, 10)
        return value if value.positive?

        raise ArgumentError
      rescue ArgumentError
        raise ConfigurationError.new(
          "hub.configuration.invalid_integer",
          "#{label} must be a positive integer"
        )
      end

      def number(source, label)
        value = Float(source)
        return value if value.positive?

        raise ArgumentError
      rescue ArgumentError
        raise ConfigurationError.new(
          "hub.configuration.invalid_number",
          "#{label} must be a positive number"
        )
      end
    end
  end
end
