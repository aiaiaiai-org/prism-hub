# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordUserIdentityRepository < Ports::UserIdentityRepository
      STATUS_ACTIVE = "active".freeze

      def provision(canonical_identity:)
        validate_canonical_identity!(canonical_identity)

        ::ActiveRecord::Base.transaction do
          record = ActiveRecordRecords::UserIdentity.lock.find_by(
            canonical_type: canonical_identity.type,
            canonical_id: canonical_identity.id
          )
          record ||= ActiveRecordRecords::UserIdentity.create!(
            canonical_type: canonical_identity.type,
            canonical_id: canonical_identity.id,
            status: STATUS_ACTIVE
          )
          ensure_active!(record)
          to_domain(record)
        end
      rescue ::ActiveRecord::RecordNotUnique
        record = ActiveRecordRecords::UserIdentity.find_by!(
          canonical_type: canonical_identity.type,
          canonical_id: canonical_identity.id
        )
        ensure_active!(record)
        to_domain(record)
      end

      def find(id:)
        record = ActiveRecordRecords::UserIdentity.find_by(id: String(id))
        record && to_domain(record)
      end

      private

      def validate_canonical_identity!(identity)
        if identity.is_a?(Domain::CanonicalIdentityRef) && identity.type == "person"
          Domain::PublicUserId.new(identity.id)
          return
        end

        raise ArgumentError, "user identities require a canonical person identity"
      end

      def ensure_active!(record)
        return if record.status == STATUS_ACTIVE

        raise UserIdentityConflictError.new(
          "hub.user_identity.disabled",
          "disabled user identities cannot be provisioned"
        )
      end

      def to_domain(record)
        Domain::UserIdentity.new(
          id: record.id,
          canonical_identity: Domain::CanonicalIdentityRef.new(
            type: record.canonical_type,
            id: record.canonical_id
          ),
          status: record.status
        )
      end
    end
  end
end
