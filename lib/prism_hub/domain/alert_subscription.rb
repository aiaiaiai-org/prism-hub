# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    # What one person asked to be told about, and roughly where they are.
    #
    # The position is a grid cell and never a coordinate: H3 resolution 6, about 3 km across. A
    # client derives the cell from the position it was given and sends only the cell, so the Hub
    # never receives where a person stands, and cannot store it.
    class AlertSubscription
      CATEGORIES = %w[drone bomb missile].freeze
      # An H3 cell index as lowercase hexadecimal. The leading `86` is the cell mode and
      # resolution 6; a coarser or finer cell, or a value that is not a cell, does not match.
      CELL_PATTERN = /\A86[0-9a-f]{13}\z/

      attr_reader :workspace_id, :cell, :categories, :include_nearby, :updated_at

      def initialize(workspace_id:, cell:, categories:, include_nearby:, updated_at:)
        @workspace_id = reference(workspace_id, "workspace_id")
        @cell = cell_value(cell)
        @categories = categories_value(categories)
        @include_nearby = boolean(include_nearby)
        @updated_at = timestamp(updated_at)
        freeze
      end

      # The public shape: exactly what the person chose, never an internal identifier.
      def to_h
        {
          "cell" => cell,
          "categories" => categories,
          "include_nearby" => include_nearby
        }
      end

      private

      def reference(value, field)
        string = String(value)
        return string.freeze if Channel::REFERENCE_PATTERN.match?(string)

        raise InputError.new(
          "hub.alert_subscription.#{field}.invalid",
          "#{field} must be a non-empty stable reference"
        )
      end

      def cell_value(value)
        string = value.is_a?(String) ? value : nil
        return string.dup.freeze if string && CELL_PATTERN.match?(string)

        raise InputError.new(
          "hub.alert_subscription.cell.invalid",
          "cell must be a resolution 6 grid cell as 15 lowercase hexadecimal digits"
        )
      end

      def categories_value(value)
        list = value.is_a?(Array) ? value : nil
        valid = list && !list.empty? && list.all? { |item| CATEGORIES.include?(item) } && list.uniq.length == list.length
        return list.sort.freeze if valid

        raise InputError.new(
          "hub.alert_subscription.categories.invalid",
          "categories must be a non-empty list of distinct values from #{CATEGORIES.join(", ")}"
        )
      end

      def boolean(value)
        return value if value == true || value == false

        raise InputError.new(
          "hub.alert_subscription.include_nearby.invalid",
          "include_nearby must be true or false"
        )
      end

      def timestamp(value)
        return value.utc.freeze if value.is_a?(Time)

        raise InputError.new(
          "hub.alert_subscription.updated_at.invalid",
          "updated_at must be a Time"
        )
      end
    end
  end
end
