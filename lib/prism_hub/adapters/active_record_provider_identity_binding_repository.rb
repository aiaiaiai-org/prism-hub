# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordProviderIdentityBindingRepository < Ports::ProviderIdentityBindingRepository
      STATUS_ACTIVE = "active".freeze
      STATUS_REVOKED = "revoked".freeze

      def bind(user_identity:, provider_subject:)
        validate_inputs!(user_identity, provider_subject)

        ::ActiveRecord::Base.transaction do
          identity_record = locked_identity(user_identity)
          existing = ActiveRecordRecords::ProviderIdentityBinding.lock.find_by(subject_key(provider_subject))
          return verify_existing!(existing, identity_record) if existing

          to_domain(
            ActiveRecordRecords::ProviderIdentityBinding.create!(
              user_identity: identity_record,
              provider: provider_subject.provider,
              provider_scope: provider_subject.provider_scope,
              subject_id: provider_subject.subject_id,
              status: STATUS_ACTIVE
            )
          )
        end
      rescue ::ActiveRecord::RecordNotUnique
        existing = ActiveRecordRecords::ProviderIdentityBinding.find_by!(subject_key(provider_subject))
        identity_record = ActiveRecordRecords::UserIdentity.find_by!(id: user_identity.id)
        verify_identity_record!(identity_record, user_identity)
        verify_existing!(existing, identity_record)
      end

      def find(provider_subject:)
        validate_provider_subject!(provider_subject)
        record = ActiveRecordRecords::ProviderIdentityBinding.includes(:user_identity).find_by(subject_key(provider_subject))
        record && to_domain(record)
      end

      def revoke(provider_subject:, revoked_at:)
        validate_provider_subject!(provider_subject)
        timestamp = normalized_timestamp(revoked_at)

        ::ActiveRecord::Base.transaction do
          record = ActiveRecordRecords::ProviderIdentityBinding.lock.find_by(subject_key(provider_subject))
          unless record
            raise ProviderIdentityBindingNotFoundError.new(
              "hub.provider_identity_binding.not_found",
              "provider identity binding was not found"
            )
          end

          if record.status == STATUS_ACTIVE
            record.update!(status: STATUS_REVOKED, revoked_at: timestamp)
          end
          to_domain(record)
        end
      end

      private

      def validate_inputs!(user_identity, provider_subject)
        unless user_identity.is_a?(Domain::UserIdentity)
          raise ArgumentError, "user_identity must be a UserIdentity"
        end
        validate_provider_subject!(provider_subject)
      end

      def validate_provider_subject!(provider_subject)
        return if provider_subject.is_a?(Domain::ProviderSubject)

        raise ArgumentError, "provider_subject must be a ProviderSubject"
      end

      def locked_identity(user_identity)
        record = ActiveRecordRecords::UserIdentity.lock.find_by(id: user_identity.id)
        unless record
          raise UserIdentityNotFoundError.new(
            "hub.user_identity.not_found",
            "user identity was not found"
          )
        end

        verify_identity_record!(record, user_identity)
        record
      end

      def verify_identity_record!(record, user_identity)
        canonical = user_identity.canonical_identity
        coherent = record.canonical_type == canonical.type && record.canonical_id == canonical.id
        unless coherent
          raise ProviderIdentityBindingConflictError.new(
            "hub.provider_identity_binding.identity_mismatch",
            "user identity does not match persisted canonical identity"
          )
        end
        if record.status != STATUS_ACTIVE || !user_identity.active?
          raise UserIdentityConflictError.new(
            "hub.user_identity.disabled",
            "disabled user identities cannot receive provider bindings"
          )
        end
      end

      def verify_existing!(record, identity_record)
        if record.status == STATUS_REVOKED
          raise ProviderIdentityBindingConflictError.new(
            "hub.provider_identity_binding.revoked",
            "revoked provider subjects require an explicit audited transfer to be rebound"
          )
        end
        if record.user_identity_id != identity_record.id
          raise ProviderIdentityBindingConflictError.new(
            "hub.provider_identity_binding.already_bound",
            "provider subject is already bound to another user identity"
          )
        end

        to_domain(record)
      end

      def subject_key(provider_subject)
        {
          provider: provider_subject.provider,
          provider_scope: provider_subject.provider_scope,
          subject_id: provider_subject.subject_id
        }
      end

      def normalized_timestamp(value)
        return value.utc if value.is_a?(Time)

        raise ArgumentError, "revoked_at must be a Time"
      end

      def to_domain(record)
        identity_record = record.user_identity
        Domain::ProviderIdentityBinding.new(
          id: record.id,
          user_identity: Domain::UserIdentity.new(
            id: identity_record.id,
            canonical_identity: Domain::CanonicalIdentityRef.new(
              type: identity_record.canonical_type,
              id: identity_record.canonical_id
            ),
            status: identity_record.status
          ),
          provider_subject: Domain::ProviderSubject.new(
            provider: record.provider,
            provider_scope: record.provider_scope,
            subject_id: record.subject_id
          ),
          status: record.status,
          revoked_at: record.revoked_at&.to_time&.utc
        )
      end
    end
  end
end
