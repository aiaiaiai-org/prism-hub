# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ActiveRecordServicePrincipalRepository < Ports::ServicePrincipalRepository
      STATUS_ACTIVE = "active".freeze

      def provision(principal_id:, capabilities:, channel_ids:)
        principal_ref = reference(principal_id, "principal_id")
        normalized_capabilities = normalize_capabilities(capabilities)
        normalized_channels = normalize_references(channel_ids, "channel_id")

        ::ActiveRecord::Base.transaction do
          principal = ActiveRecordRecords::ServicePrincipal.lock.find_by(identifier: principal_ref)

          if principal
            verify_existing!(principal, normalized_capabilities, normalized_channels)
          else
            principal = create_principal(
              principal_ref,
              normalized_capabilities,
              normalized_channels
            )
          end

          principal.identifier
        end
      rescue ::ActiveRecord::RecordNotUnique
        verify_concurrent_provisioning!(
          principal_ref,
          normalized_capabilities,
          normalized_channels
        )
      end

      private

      def create_principal(identifier, capabilities, channel_ids)
        principal = ActiveRecordRecords::ServicePrincipal.create!(
          identifier: identifier,
          status: STATUS_ACTIVE
        )
        capabilities.each { |capability| principal.capability_grants.create!(capability: capability) }
        channel_ids.each { |channel_id| principal.channel_grants.create!(channel_id: channel_id) }
        principal
      end

      def verify_concurrent_provisioning!(principal_id, capabilities, channel_ids)
        principal = ActiveRecordRecords::ServicePrincipal.find_by(identifier: principal_id)
        unless principal
          raise ServicePrincipalConflictError.new(
            "hub.service_principal.conflict",
            "service principal identity is already bound"
          )
        end

        verify_existing!(principal, capabilities, channel_ids)
        principal.identifier
      end

      def verify_existing!(principal, capabilities, channel_ids)
        if principal.status != STATUS_ACTIVE
          raise ServicePrincipalConflictError.new(
            "hub.service_principal.disabled",
            "disabled service principals cannot be provisioned"
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
