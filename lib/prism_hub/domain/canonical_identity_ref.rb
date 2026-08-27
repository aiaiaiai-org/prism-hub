# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class CanonicalIdentityRef
      TYPES = %w[person organization agent project product].freeze
      MAX_ID_LENGTH = 255

      attr_reader :type, :id

      def initialize(type:, id:)
        @type = normalize_type(type)
        @id = normalize_id(id)
        freeze
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.id == id
      end
      alias eql? ==

      def hash
        [self.class, type, id].hash
      end

      def to_s
        "#{type}:#{id}"
      end

      private

      def normalize_type(value)
        string = String(value)
        return string.freeze if TYPES.include?(string)

        raise InputError.new(
          "hub.identity.type.invalid",
          "canonical identity type is not supported"
        )
      end

      def normalize_id(value)
        string = String(value)
        return string.freeze if !string.empty? && string.length <= MAX_ID_LENGTH

        raise InputError.new(
          "hub.identity.id.invalid",
          "canonical identity id must contain 1 to #{MAX_ID_LENGTH} characters"
        )
      end
    end
  end
end
