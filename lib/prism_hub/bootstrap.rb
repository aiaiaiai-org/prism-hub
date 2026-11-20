# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  class Bootstrap
    AIS_ISSUER = "https://auth.aiaiaiai.org".freeze
    AIS_AUDIENCE = "prism-hub".freeze

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
        binding_repository = Adapters::ActiveRecordTelegramSurfaceBindingRepository.new

        list_channels = UseCases::ListChannels.new(channel_repository: channels)
        resolve_actor = UseCases::ResolveWorkspaceActor.new(
          binding_repository: Adapters::ActiveRecordProviderIdentityBindingRepository.new,
          workspace_membership_repository: Adapters::ActiveRecordWorkspaceMembershipRepository.new
        )
        resolve_personal_actor = UseCases::ResolvePersonalActor.new(
          binding_repository: Adapters::ActiveRecordProviderIdentityBindingRepository.new,
          workspace_membership_repository: Adapters::ActiveRecordWorkspaceMembershipRepository.new,
          workspace_id_factory: Adapters::PersonalWorkspaceIdFactory.new
        )
        onboard_actor = UseCases::OnboardProviderIdentity.new(
          onboarding_repository: Adapters::ActiveRecordIdentityOnboardingRepository.new,
          public_user_id_generator: Adapters::SecurePublicUserIdGenerator.new
        )
        bot_lifecycle = UseCases::PersonalBotLifecycle.new(
          resolve_personal_actor: resolve_personal_actor,
          bot_instance_repository: Adapters::ActiveRecordBotInstanceRepository.new,
          clock: clock
        )
        alert_subscription = UseCases::PersonalAlertSubscription.new(
          resolve_personal_actor: resolve_personal_actor,
          alert_subscription_repository: Adapters::ActiveRecordAlertSubscriptionRepository.new,
          clock: clock
        )
        bind_telegram_surface = UseCases::BindTelegramSurface.new(
          resolve_workspace_actor: resolve_actor,
          binding_repository: binding_repository,
          bot_instance_repository: Adapters::ActiveRecordBotInstanceRepository.new
        )
        validate = execution_use_case("validate", channels: channels, gateway: gateway)
        publish = execution_use_case("publish", channels: channels, gateway: gateway)
        credential_repository = Adapters::ActiveRecordClientCredentialRepository.new
        authenticator = Interfaces::Http::Authenticator.new(
          credential_repository: credential_repository,
          clock: clock,
          **legacy_authentication(env, channels),
          **product_authentication(env, logger)
        )

        Interfaces::Http::App.new(
          authenticator: authenticator,
          health_endpoint: Interfaces::Http::HealthEndpoint.new,
          routes: {
            ["POST", "/api/v1/actors/personal/resolve"] =>
              Interfaces::Http::PersonalActorResolutionEndpoint.new(
                resolve_personal_actor: resolve_personal_actor,
                request_body: request_body
              ),
            ["POST", "/api/v1/actors/onboard"] => Interfaces::Http::ActorOnboardingEndpoint.new(
              onboard_provider_identity: onboard_actor,
              request_body: request_body
            ),
            ["POST", "/api/v1/actors/resolve"] => Interfaces::Http::ActorResolutionEndpoint.new(
              resolve_workspace_actor: resolve_actor,
              request_body: request_body
            ),
            ["POST", "/api/v1/bot-instances/personal/status"] => lifecycle_endpoint(bot_lifecycle, :status, request_body),
            ["POST", "/api/v1/bot-instances/personal/pause"] => lifecycle_endpoint(bot_lifecycle, :pause, request_body),
            ["POST", "/api/v1/bot-instances/personal/resume"] => lifecycle_endpoint(bot_lifecycle, :resume, request_body),
            ["POST", "/api/v1/alert-subscriptions/personal/status"] =>
              alert_subscription_endpoint(alert_subscription, :status, request_body),
            ["POST", "/api/v1/alert-subscriptions/personal/save"] =>
              alert_subscription_endpoint(alert_subscription, :save, request_body),
            ["POST", "/api/v1/alert-subscriptions/personal/clear"] =>
              alert_subscription_endpoint(alert_subscription, :clear, request_body),
            ["POST", "/api/v1/telegram/surfaces/bind"] =>
              Interfaces::Http::TelegramSurfaceBindingEndpoint.new(
                bind_telegram_surface: bind_telegram_surface,
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

      def lifecycle_endpoint(lifecycle, operation, request_body)
        Interfaces::Http::PersonalBotLifecycleEndpoint.new(lifecycle: lifecycle, operation: operation, request_body: request_body)
      end

      def alert_subscription_endpoint(subscription, operation, request_body)
        Interfaces::Http::PersonalAlertSubscriptionEndpoint.new(
          subscription: subscription,
          operation: operation,
          request_body: request_body
        )
      end

      # Both the token issuer and its JWKS must come from the same trust domain.
      def product_authentication(env, logger)
        issuer = product_issuer(env)
        return {} unless issuer

        {
          product_token_verifier: Adapters::AisProductTokenVerifier.new(
            issuer: issuer,
            audience: AIS_AUDIENCE,
            key_source: Adapters::HttpAisKeySource.new(issuer: issuer, logger: logger)
          ),
          principal_repository: Adapters::ActiveRecordServicePrincipalRepository.new
        }
      end

      # The AIS trust environment is a deployment declaration, not the Rails mode: the shipped image
      # is always RAILS_ENV=production, development included. Development trust is never inferred
      # from, and never falls back to, production: without a configured isolated origin, no AIS
      # product token is accepted.
      def product_issuer(env)
        development_issuer = env.fetch("PRISM_HUB_DEVELOPMENT_AIS_ISSUER", "")
        case ais_environment(env)
        when "production"
          return AIS_ISSUER if development_issuer.empty?

          raise ConfigurationError.new(
            "hub.ais_issuer.invalid",
            "a development AIS origin needs PRISM_HUB_AIS_ENVIRONMENT=development"
          )
        when "development"
          development_issuer.empty? ? nil : development_origin(development_issuer)
        end
      end

      # Undeclared, the Rails mode decides, as before: a production Hub keeps its pinned issuer
      # and a local development or test Hub accepts none. A development workload on the production
      # image must declare `development`.
      def ais_environment(env)
        declared = env.fetch("PRISM_HUB_AIS_ENVIRONMENT", "")
        return declared if %w[production development].include?(declared)
        unless declared.empty?
          raise ConfigurationError.new("hub.ais_environment.invalid", "PRISM_HUB_AIS_ENVIRONMENT must be production or development")
        end

        case env.fetch("RAILS_ENV") { env.fetch("RACK_ENV", "development") }
        when "production" then "production"
        when "development", "test" then "development"
        else raise ConfigurationError.new("hub.ais_issuer.invalid", "unknown Hub environment")
        end
      end

      # Require a canonical HTTPS origin. In particular, aliases with the
      # production hostname spelled differently are not a separate issuer.
      def development_origin(origin)
        unless origin.match?(/\Ahttps:\/\/[a-z0-9-]+(?:\.[a-z0-9-]+)+\z/) &&
            ![AIS_ISSUER, "https://www.auth.aiaiaiai.org"].include?(origin)
          raise ConfigurationError.new("hub.ais_issuer.invalid", "development Hub needs an isolated HTTPS AIS origin")
        end
        origin
      end

      def legacy_authentication(env, channels)
        enabled = boolean(env.fetch("PRISM_HUB_LEGACY_TOKEN_ENABLED", "false"), "legacy token flag")
        return {} unless enabled
        {
          legacy_token: env.fetch("PRISM_HUB_API_TOKEN"),
          legacy_context: Domain::AuthorisationContext.new(
            principal_id: "legacy-global",
            capabilities: Domain::Capabilities::ALL,
            allowed_channel_ids: channels.all_ids
          )
        }
      end

      def build_gateway(env, logger)
        runner = Adapters::ProcessRunner.new(
          command: command(env.fetch("PRISM_RUNTIME_COMMAND_JSON", '["prism-runtime","--json"]')),
          environment: {"RUST_LOG" => env.fetch("PRISM_RUNTIME_LOG", "warn")},
          timeout_seconds: number(env.fetch("PRISM_RUNTIME_TIMEOUT_SECONDS", "10"), "runtime timeout")
        )
        Adapters::SubprocessExecutionGateway.new(runner: runner, logger: logger)
      end

      def execution_use_case(operation, channels:, gateway:)
        UseCases::ExecutePublication.new(operation: operation, channel_repository: channels, execution_gateway: gateway)
      end

      def command(source)
        value = JSON.parse(source)
        return value.freeze if value.is_a?(Array) && value.any? && value.all? { |part| part.is_a?(String) && !part.empty? }
        raise ConfigurationError.new("hub.prism.command.invalid", "PRISM_RUNTIME_COMMAND_JSON must be a non-empty JSON string array")
      rescue JSON::ParserError
        raise ConfigurationError.new("hub.prism.command.invalid_json", "PRISM_RUNTIME_COMMAND_JSON must contain valid JSON")
      end

      def boolean(source, label)
        return true if source == "true"
        return false if source == "false"
        raise ConfigurationError.new("hub.configuration.invalid_boolean", "#{label} must be true or false")
      end

      def integer(source, label)
        value = Integer(source, 10)
        return value if value.positive?
        raise ArgumentError
      rescue ArgumentError
        raise ConfigurationError.new("hub.configuration.invalid_integer", "#{label} must be a positive integer")
      end

      def number(source, label)
        value = Float(source)
        return value if value.positive?
        raise ArgumentError
      rescue ArgumentError
        raise ConfigurationError.new("hub.configuration.invalid_number", "#{label} must be a positive number")
      end
    end
  end
end
