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
        return nil unless principal.status == STATUS_ACTIVE

        Domain::AuthorisationContext.new(
          principal_id: principal.identifier,
          capabilities: principal.capability_grants.map(&:capability),
          allowed_channel_ids: principal.channel_grants.map(&:channel_id)
        )
      end

      def issue(principal_id:, token:, expires_at:)
        validate_token!(token)
        principal_ref = reference(principal_id, "principal_id")

        credential = ::ActiveRecord::Base.transaction do
          principal = find_active_principal!(principal_ref)
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
          "generated client credential collides with an existing credential"
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
          service_principal: [:capability_grants, :channel_grants]
        )
      end

      def find_active_principal!(principal_id)
        principal = ActiveRecordRecords::ServicePrincipal.lock.find_by(identifier: principal_id)
        unless principal
          raise ServicePrincipalNotFoundError.new(
            "hub.service_principal.not_found",
            "service principal does not exist"
          )
        end
        if principal.status != STATUS_ACTIVE
          raise ServicePrincipalConflictError.new(
            "hub.service_principal.disabled",
            "disabled service principals cannot receive client credentials"
          )
        end

        principal
      end

      def token_digest(token)
        Digest::SHA256.hexdigest(String(token))
      end

      def validate_token!(token)
        return if TOKEN_PATTERN.match?(String(token))

        raise ArgumentError, "client credential token has an invalid format"
      end

      def reference(value, field)
        string = String(value)
        return string if Domain::Channel::REFERENCE_PATTERN.match?(string)

        raise ArgumentError, "#{field} must be a non-empty stable reference"
      end
    end
  end
end
