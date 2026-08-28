# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class BotInstance
      STATUSES = %w[active paused disabled].freeze

      attr_reader :id, :principal_id, :workspace_id, :status, :paused_at, :disabled_at

      def initialize(id:, principal_id:, workspace_id:, status:, paused_at: nil, disabled_at: nil)
        @id = reference(id, "id")
        @principal_id = reference(principal_id, "principal_id")
        @workspace_id = reference(workspace_id, "workspace_id")
        @status = normalize_status(status)
        @paused_at = timestamp(paused_at, "paused_at")
        @disabled_at = timestamp(disabled_at, "disabled_at")
        validate_state!
        freeze
      end

      def active?
        status == "active"
      end

      def paused?
        status == "paused"
      end

      def disabled?
        status == "disabled"
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze if Channel::REFERENCE_PATTERN.match?(string)

        raise InputError.new(
          "hub.bot_instance.#{field}.invalid",
          "#{field} must be a non-empty stable reference"
        )
      end

      def normalize_status(value)
        string = String(value)
        return string.freeze if STATUSES.include?(string)

        raise InputError.new(
          "hub.bot_instance.status.invalid",
          "bot instance status is invalid"
        )
      end

      def timestamp(value, field)
        return nil if value.nil?
        return value.utc.freeze if value.is_a?(Time)

        raise InputError.new(
          "hub.bot_instance.#{field}.invalid",
          "#{field} must be a Time"
        )
      end

      def validate_state!
        coherent = case status
        when "active"
          paused_at.nil? && disabled_at.nil?
        when "paused"
          !paused_at.nil? && disabled_at.nil?
        when "disabled"
          paused_at.nil? && !disabled_at.nil?
        end
        return if coherent

        raise InputError.new(
          "hub.bot_instance.state.invalid",
          "bot instance status and lifecycle timestamps are inconsistent"
        )
      end
    end
  end
end
