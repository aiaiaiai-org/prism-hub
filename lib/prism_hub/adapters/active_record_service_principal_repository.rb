# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordServicePrincipalRepository < Ports::ServicePrincipalRepository
      STATUS_ACTIVE = "active".freeze

      def provision(workspace_id:, principal_id:, bot_instance_id:, capabilities:, channel_ids:)
        workspace_ref = reference(workspace_id, "workspace_id")
        principal_ref = reference(principal_id, "principal_id")
        bot_ref = reference(bot_instance_id, "bot_instance_id")
        normalized_capabilities = normalize_capabilities(capabilities)
        normalized_channels = normalize_references(channel_ids, "channel_id")

        ::ActiveRecord::Base.transaction do
          workspace = find_or_create_workspace(workspace_ref)
          workspace.lock!
          principal = ActiveRecordRecords::ServicePrincipal.lock.find_by(
            workspace: workspace,
            identifier: principal_ref
          )

          if principal
            verify_existing!(principal, bot_ref, normalized_capabilities, normalized_channels)
          else
            principal = create_principal(
              workspace,
              principal_ref,
              bot_ref,
              normalized_capabilities,
              normalized_channels
            )
          end

          principal.identifier
        end
      rescue ::ActiveRecord::RecordNotUnique
        verify_concurrent_provisioning!(
          workspace_ref,
          principal_ref,
          bot_ref,
          normalized_capabilities,
          normalized_channels
        )
      end

      private

      def find_or_create_workspace(identifier)
        workspace = ActiveRecordRecords::Workspace.find_or_create_by!(identifier: identifier) do |record|
          record.status = STATUS_ACTIVE
        end
        ensure_workspace_active!(workspace)
        workspace
      end

      def ensure_workspace_active!(workspace)
        return if workspace.status == STATUS_ACTIVE

        raise ServicePrincipalConflictError.new(
          "hub.workspace.disabled",
          "disabled workspaces cannot receive service principals"
        )
      end

      def create_principal(workspace, identifier, bot_instance_id, capabilities, channel_ids)
        principal = ActiveRecordRecords::ServicePrincipal.create!(
          workspace: workspace,
          identifier: identifier,
          bot_instance_id: bot_instance_id,
          status: STATUS_ACTIVE
        )
        capabilities.each { |capability| principal.capability_grants.create!(capability: capability) }
        channel_ids.each { |channel_id| principal.channel_grants.create!(channel_id: channel_id) }
        principal
      end

      def verify_concurrent_provisioning!(workspace_id, principal_id, bot_instance_id, capabilities, channel_ids)
        workspace = ActiveRecordRecords::Workspace.find_by(identifier: workspace_id)
        principal = workspace && ActiveRecordRecords::ServicePrincipal.find_by(
          workspace: workspace,
          identifier: principal_id
        )
        unless principal
          raise ServicePrincipalConflictError.new(
            "hub.service_principal.conflict",
            "service principal identity or bot instance is already bound"
          )
        end

        ensure_workspace_active!(workspace)
        verify_existing!(principal, bot_instance_id, capabilities, channel_ids)
        principal.identifier
      end

      def verify_existing!(principal, bot_instance_id, capabilities, channel_ids)
        if principal.status != STATUS_ACTIVE
          raise ServicePrincipalConflictError.new(
            "hub.service_principal.disabled",
            "disabled service principals cannot be provisioned"
          )
        end

        if principal.bot_instance_id != bot_instance_id
          raise ServicePrincipalConflictError.new(
            "hub.service_principal.bot_instance_mismatch",
            "service principal is already bound to another bot instance"
          )
        end

        actual_capabilities = principal.capability_grants.pluck(:capability).sort
        actual_channels = principal.channel_grants.pluck(:channel_id).sort
        return if actual_capabilities == capabilities && actual_channels == channel_ids

        raise ServicePrincipalConflictError.new(
          "hub.service_principal.grants_mismatch",
          "service principal grants differ; change grants through an explicit grant operation"
        )
      end

      def normalize_capabilities(values)
        Array(values).map do |value|
          string = String(value)
          unless Domain::AuthorisationContext::CAPABILITY_PATTERN.match?(string)
            raise ArgumentError, "capability must use a namespace:action reference"
          end
          unless Domain::Capabilities::ALL.include?(string)
            raise ArgumentError, "capability is not supported by this Hub API version"
          end
          string
        end.uniq.sort.freeze
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
