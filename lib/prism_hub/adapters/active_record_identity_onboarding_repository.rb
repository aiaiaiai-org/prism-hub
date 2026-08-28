# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordIdentityOnboardingRepository < Ports::IdentityOnboardingRepository
      STATUS_ACTIVE = "active".freeze
      STATUS_REVOKED = "revoked".freeze
      ROLE_OWNER = "owner".freeze

      def initialize(workspace_id_factory: PersonalWorkspaceIdFactory.new)
        @workspace_id_factory = workspace_id_factory
      end

      def resolve_or_create(provider_subject:, public_user_id:)
        validate_provider_subject!(provider_subject)
        candidate = Domain::PublicUserId.new(public_user_id).to_s

        ::ActiveRecord::Base.transaction do
          binding = ActiveRecordRecords::ProviderIdentityBinding.lock
            .includes(:user_identity)
            .find_by(subject_key(provider_subject))
          if binding
            ensure_personal_membership!(binding)
          else
            create_onboarding!(provider_subject, candidate)
          end
        end
      rescue ::ActiveRecord::RecordNotUnique
        binding = ActiveRecordRecords::ProviderIdentityBinding.includes(:user_identity)
          .find_by(subject_key(provider_subject))
        return ensure_existing_after_race!(binding) if binding

        raise PublicUserIdConflictError.new(
          "hub.user_identity.public_id.conflict",
          "the generated public user id collided"
        )
      end

      private

      def create_onboarding!(provider_subject, public_user_id)
        identity = ActiveRecordRecords::UserIdentity.create!(
          canonical_type: "person",
          canonical_id: public_user_id,
          status: STATUS_ACTIVE
        )
        workspace = ActiveRecordRecords::Workspace.create!(
          identifier: @workspace_id_factory.call(public_user_id),
          status: STATUS_ACTIVE
        )
        ActiveRecordRecords::ProviderIdentityBinding.create!(
          user_identity: identity,
          provider: provider_subject.provider,
          provider_scope: provider_subject.provider_scope,
          subject_id: provider_subject.subject_id,
          status: STATUS_ACTIVE
        )
        to_domain(
          ActiveRecordRecords::WorkspaceMembership.create!(
            workspace: workspace,
            user_identity: identity,
            role: ROLE_OWNER,
            status: STATUS_ACTIVE
          )
        )
      end

      def ensure_existing_after_race!(binding)
        ::ActiveRecord::Base.transaction do
          locked = ActiveRecordRecords::ProviderIdentityBinding.lock
            .includes(:user_identity)
            .find(binding.id)
          ensure_personal_membership!(locked)
        end
      end

      def ensure_personal_membership!(binding)
        deny_onboarding! unless binding.status == STATUS_ACTIVE

        identity = ActiveRecordRecords::UserIdentity.lock.find(binding.user_identity_id)
        deny_onboarding! unless identity.status == STATUS_ACTIVE
        public_user_id = Domain::PublicUserId.new(identity.canonical_id).to_s
        workspace_id = @workspace_id_factory.call(public_user_id)
        workspace = ActiveRecordRecords::Workspace.lock.find_by(identifier: workspace_id)
        workspace ||= ActiveRecordRecords::Workspace.create!(identifier: workspace_id, status: STATUS_ACTIVE)
        deny_onboarding! unless workspace.status == STATUS_ACTIVE

        membership = ActiveRecordRecords::WorkspaceMembership.lock.find_by(
          workspace: workspace,
          user_identity: identity
        )
        if membership
          deny_onboarding! unless membership.status == STATUS_ACTIVE && membership.role == ROLE_OWNER
          return to_domain(membership)
        end

        occupied = ActiveRecordRecords::WorkspaceMembership.where(workspace: workspace).exists?
        deny_onboarding! if occupied
        to_domain(
          ActiveRecordRecords::WorkspaceMembership.create!(
            workspace: workspace,
            user_identity: identity,
            role: ROLE_OWNER,
            status: STATUS_ACTIVE
          )
        )
      rescue InputError
        deny_onboarding!
      end

      def validate_provider_subject!(provider_subject)
        return if provider_subject.is_a?(Domain::ProviderSubject)

        raise ArgumentError, "provider_subject must be a ProviderSubject"
      end

      def subject_key(provider_subject)
        {
          provider: provider_subject.provider,
          provider_scope: provider_subject.provider_scope,
          subject_id: provider_subject.subject_id
        }
      end

      def deny_onboarding!
        raise IdentityOnboardingDeniedError.new(
          "hub.identity_onboarding.denied",
          "the provider identity cannot be onboarded"
        )
      end

      def to_domain(record)
        identity = record.user_identity
        Domain::WorkspaceMembership.new(
          id: record.id,
          workspace_id: record.workspace.identifier,
          user_identity: Domain::UserIdentity.new(
            id: identity.id,
            canonical_identity: Domain::CanonicalIdentityRef.new(
              type: identity.canonical_type,
              id: identity.canonical_id
            ),
            status: identity.status
          ),
          role: record.role,
          status: record.status,
          revoked_at: record.revoked_at&.to_time&.utc
        )
      end
    end
  end
end
