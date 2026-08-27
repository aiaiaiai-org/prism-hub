# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    module ActiveRecordRecords
      class Workspace < ::ActiveRecord::Base
        self.table_name = "workspaces"

        has_many :service_principals,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal",
          inverse_of: :workspace,
          dependent: :restrict_with_exception
        has_many :workspace_memberships,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::WorkspaceMembership",
          inverse_of: :workspace,
          dependent: :restrict_with_exception
      end

      class ServicePrincipal < ::ActiveRecord::Base
        self.table_name = "service_principals"

        belongs_to :workspace,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::Workspace",
          inverse_of: :service_principals
        has_many :client_credentials,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::ClientCredential",
          inverse_of: :service_principal,
          dependent: :delete_all
        has_many :capability_grants,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::CapabilityGrant",
          inverse_of: :service_principal,
          dependent: :delete_all
        has_many :channel_grants,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::ChannelGrant",
          inverse_of: :service_principal,
          dependent: :delete_all
      end

      class ClientCredential < ::ActiveRecord::Base
        self.table_name = "client_credentials"

        belongs_to :service_principal,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal",
          inverse_of: :client_credentials
      end

      class CapabilityGrant < ::ActiveRecord::Base
        self.table_name = "capability_grants"

        belongs_to :service_principal,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal",
          inverse_of: :capability_grants
      end

      class ChannelGrant < ::ActiveRecord::Base
        self.table_name = "channel_grants"

        belongs_to :service_principal,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::ServicePrincipal",
          inverse_of: :channel_grants
      end

      class UserIdentity < ::ActiveRecord::Base
        self.table_name = "user_identities"

        has_many :provider_identity_bindings,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::ProviderIdentityBinding",
          inverse_of: :user_identity,
          dependent: :restrict_with_exception
        has_many :workspace_memberships,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::WorkspaceMembership",
          inverse_of: :user_identity,
          dependent: :restrict_with_exception
      end

      class ProviderIdentityBinding < ::ActiveRecord::Base
        self.table_name = "provider_identity_bindings"

        belongs_to :user_identity,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::UserIdentity",
          inverse_of: :provider_identity_bindings
      end

      class WorkspaceMembership < ::ActiveRecord::Base
        self.table_name = "workspace_memberships"

        belongs_to :workspace,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::Workspace",
          inverse_of: :workspace_memberships
        belongs_to :user_identity,
          class_name: "PrismHub::Adapters::ActiveRecordRecords::UserIdentity",
          inverse_of: :workspace_memberships
      end
    end
  end
end
