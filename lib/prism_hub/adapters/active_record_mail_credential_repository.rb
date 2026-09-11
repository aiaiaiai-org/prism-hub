# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Adapters
    class ActiveRecordMailCredentialRepository < Ports::MailCredentialRepository
      Credential = Data.define(
        :provider,
        :origin,
        :resource,
        :oauth_client_id,
        :access_token,
        :refresh_token,
        :scope,
        :token_type,
        :expires_at
      )

      def initialize(cipher:)
        @cipher = cipher
      end

      def store(provider:, origin:, resource:, oauth_client_id:, access_token:, refresh_token:, scope:, token_type:, expires_at:)
        encrypted_access_token = @cipher.encrypt(access_token)
        encrypted_refresh_token = refresh_token && @cipher.encrypt(refresh_token)

        ::ActiveRecord::Base.transaction do
          record = ActiveRecordRecords::MailProviderCredential.lock.find_or_initialize_by(
            provider: provider,
            origin: origin,
            resource: resource
          )
          record.assign_attributes(
            oauth_client_id: oauth_client_id,
            access_token_ciphertext: encrypted_access_token,
            refresh_token_ciphertext: encrypted_refresh_token,
            scope: Array(scope).join(" "),
            token_type: token_type,
            expires_at: expires_at,
            status: "active",
            revoked_at: nil
          )
          record.save!
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => error
        raise CredentialConflictError.new(
          "hub.mail.credential.store_failed",
          "mail credential could not be stored",
          details: {"cause" => error.class.name}
        )
      end

      def fetch(provider:, origin:, resource:)
        record = ActiveRecordRecords::MailProviderCredential.find_by(
          provider: provider,
          origin: origin,
          resource: resource,
          status: "active"
        )
        return unless record

        Credential.new(
          provider: record.provider,
          origin: record.origin,
          resource: record.resource,
          oauth_client_id: record.oauth_client_id,
          access_token: @cipher.decrypt(record.access_token_ciphertext),
          refresh_token: record.refresh_token_ciphertext && @cipher.decrypt(record.refresh_token_ciphertext),
          scope: record.scope.split,
          token_type: record.token_type,
          expires_at: record.expires_at
        )
      end
    end
  end
end
