# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class WorkspaceActorContext
      attr_reader :principal_id, :workspace_id, :user_identity, :role, :provider_subject

      def initialize(principal_id:, workspace_id:, user_identity:, role:, provider_subject:)
        unless user_identity.is_a?(UserIdentity)
          raise InputError.new(
            "hub.actor.user_identity.invalid",
            "workspace actor context requires a user identity"
          )
        end
        unless provider_subject.is_a?(ProviderSubject)
          raise InputError.new(
            "hub.actor.provider_subject.invalid",
            "workspace actor context requires a provider subject"
          )
        end

        @principal_id = reference(principal_id, "principal_id")
        @workspace_id = reference(workspace_id, "workspace_id")
        @user_identity = user_identity
        @role = normalized_role(role)
        @provider_subject = provider_subject
        freeze
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze if Channel::REFERENCE_PATTERN.match?(string)

        raise InputError.new(
          "hub.actor.#{field}.invalid",
          "#{field} must be a non-empty stable reference"
        )
      end

      def normalized_role(value)
        string = String(value)
        return string.freeze if WorkspaceMembership::ROLES.include?(string)

        raise InputError.new(
          "hub.actor.role.invalid",
          "workspace actor role is invalid"
        )
      end
    end
  end
end
