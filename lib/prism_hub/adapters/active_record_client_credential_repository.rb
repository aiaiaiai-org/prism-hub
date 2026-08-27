# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordClientCredentialRepository < Ports::ClientCredentialRepository
      TOKEN_PATTERN = /\Aprism_client_v1_[A-Za-z0-9_-]{43}\z/
      STATUS_ACTIVE = "active".freeze

      def authenticate(token:, now:)
        return nil unless TOKEN_PATTERN.match?(String(token))

        credential = credential_scope.find_by(token_digest: token_digest(token))
        return nil unless credential
        return nil if credential.revoked_at
        return nil if credential.expires_at && credential.expires_at <= now

        principal = credential.service_principal
        workspace = principal.workspace
        return nil unless principal.status == STATUS_ACTIVE && workspace.status == STATUS_ACTIVE

        Domain::AuthorisationContext.new(
          principal_id: principal.identifier,
          workspace_id: workspace.identifier,
          capabilities: principal.capability_grants.map(&:capability),
          allowed_channel_ids: principal.channel_grants.map(&:channel_id)
        )
      end

      def issue(workspace_id:, principal_id:, bot_instance_id:, capabilities:, channel_ids:, token:, expires_at:)
        validate_token!(token)
        normalized_capabilities = normalize_capabilities(capabilities)
        normalized_channels = normalize_references(channel_ids, "channel_id")
        workspace_ref = reference(workspace_id, "workspace_id")
        principal_ref = reference(principal_id, "principal_id")
        bot_ref = reference(bot_instance_id, "bot_instance_id")

        credential = ::ActiveRecord::Base.transaction do
          workspace = find_or_create_workspace(workspace_ref)
          principal = find_or_create_principal(workspace, principal_ref, bot_ref)
          synchronize_grants(principal, normalized_capabilities, normalized_channels)
          ActiveRecordRecords::ClientCredential.create!(
            service_principal: principal,
            token_digest: token_digest(token),
            expires_at: expires_at
          )
        end

        credential.id.to_s
      rescue ::ActiveRecord::RecordNotUnique
        raise CredentialConflictError.new(
          "hub.client_credential.conflict",
          "client credential or principal identity already exists"
        )
      end

      def rotate(credential_id:, token:, rotated_at:, expires_at:)
        validate_token!(token)

        ::ActiveRecord::Base.transaction do
          current = ActiveRecordRecords::ClientCredential.lock.find(credential_id)
          if current.revoked_at
            raise CredentialConflictError.new(
              "hub.client_credential.revoked",
              "revoked credentials cannot be rotated"
            )
          end

          replacement = ActiveRecordRecords::ClientCredential.create!(
            service_principal: current.service_principal,
            token_digest: token_digest(token),
            expires_at: expires_at
          )
          current.update!(revoked_at: rotated_at)
          replacement.id.to_s
        end
      rescue ::ActiveRecord::RecordNotFound
        raise CredentialNotFoundError.new(
          "hub.client_credential.not_found",
          "client credential does not exist"
        )
      rescue ::ActiveRecord::RecordNotUnique
        raise CredentialConflictError.new(
          "hub.client_credential.conflict",
          "generated client credential collides with an existing credential"
        )
      end

      def revoke(credential_id:, revoked_at:)
        ::ActiveRecord::Base.transaction do
          credential = ActiveRecordRecords::ClientCredential.lock.find(credential_id)
          credential.update!(revoked_at: revoked_at) unless credential.revoked_at
          credential.id.to_s
        end
      rescue ::ActiveRecord::RecordNotFound
        raise CredentialNotFoundError.new(
          "hub.client_credential.not_found",
          "client credential does not exist"
        )
      end

      private

      def credential_scope
        ActiveRecordRecords::ClientCredential.includes(
          service_principal: [:workspace, :capability_grants, :channel_grants]
        )
      end

      def find_or_create_workspace(identifier)
        workspace = ActiveRecordRecords::Workspace.find_or_create_by!(identifier: identifier) do |record|
          record.status = STATUS_ACTIVE
        end
        return workspace if workspace.status == STATUS_ACTIVE

        raise CredentialConflictError.new(
          "hub.workspace.disabled",
          "disabled workspaces cannot receive new client credentials"
        )
      end

      def find_or_create_principal(workspace, identifier, bot_instance_id)
        principal = ActiveRecordRecords::ServicePrincipal.find_or_initialize_by(
          workspace: workspace,
          identifier: identifier
        )
        if principal.new_record?
          principal.bot_instance_id = bot_instance_id
          principal.status = STATUS_ACTIVE
          principal.save!
        elsif principal.bot_instance_id != bot_instance_id
          raise CredentialConflictError.new(
            "hub.service_principal.bot_instance_mismatch",
            "service principal is already bound to another bot instance"
          )
        elsif principal.status != STATUS_ACTIVE
          raise CredentialConflictError.new(
            "hub.service_principal.disabled",
            "disabled service principals cannot receive new client credentials"
          )
        end
        principal
      end

      def synchronize_grants(principal, capabilities, channel_ids)
        replace_values(principal.capability_grants, :capability, capabilities)
        replace_values(principal.channel_grants, :channel_id, channel_ids)
      end

      def replace_values(association, attribute, desired_values)
        existing = association.to_a.to_h { |record| [record.public_send(attribute), record] }
        (existing.keys - desired_values).each { |value| existing.fetch(value).destroy! }
        (desired_values - existing.keys).each { |value| association.create!(attribute => value) }
      end

      def token_digest(token)
        Digest::SHA256.hexdigest(String(token))
      end

      def validate_token!(token)
        return if TOKEN_PATTERN.match?(String(token))

        raise ArgumentError, "client credential token has an invalid format"
      end

      def normalize_capabilities(values)
        normalized = Array(values).map do |value|
          string = String(value)
          unless Domain::AuthorisationContext::CAPABILITY_PATTERN.match?(string)
            raise ArgumentError, "capability must use a namespace:action reference"
          end
          string
        end
        normalized.uniq.sort.freeze
      end

      def normalize_references(values, field)
        Array(values).map { |value| reference(value, field) }.uniq.sort.freeze
      end

      def reference(value, field)
        string = String(value)
        return string if Domain::Channel::REFERENCE_PATTERN.match?(string)

        raise ArgumentError, "#{field} must be a non-empty stable reference"
      end
    end
  end
end
