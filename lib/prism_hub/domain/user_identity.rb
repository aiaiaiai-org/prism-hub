# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class UserIdentity
      STATUSES = %w[active disabled].freeze

      attr_reader :id, :canonical_identity, :status

      def initialize(id:, canonical_identity:, status:)
        unless canonical_identity.is_a?(CanonicalIdentityRef) && canonical_identity.type == "person"
          raise InputError.new(
            "hub.user_identity.subject.invalid",
            "user identities must reference a canonical person identity"
          )
        end

        @id = reference(id, "id")
        @canonical_identity = canonical_identity
        @status = normalize_status(status)
        freeze
      end

      def active?
        status == "active"
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze unless string.empty?

        raise InputError.new(
          "hub.user_identity.#{field}.invalid",
          "#{field} must be a non-empty reference"
        )
      end

      def normalize_status(value)
        string = String(value)
        return string.freeze if STATUSES.include?(string)

        raise InputError.new(
          "hub.user_identity.status.invalid",
          "user identity status is invalid"
        )
      end
    end
  end
end
