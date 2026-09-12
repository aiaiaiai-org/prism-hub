# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class Mailbox
      IDENTIFIER_PATTERN = /\A[^[:cntrl:]\s]{1,100}\z/

      attr_reader :id, :address, :display_name, :is_active, :access_level

      def initialize(id:, address:, display_name:, is_active:, access_level:)
        @id = required_identifier(id, "id")
        @address = required_text(address, "address", 320)
        @display_name = required_text(display_name, "display_name", 200)
        @is_active = required_boolean(is_active, "is_active")
        @access_level = required_text(access_level, "access_level", 64)
        freeze
      end

      def public_attributes
        {
          "id" => id,
          "address" => address,
          "display_name" => display_name,
          "is_active" => is_active,
          "access_level" => access_level
        }.freeze
      end

      private

      def required_identifier(value, field)
        string = String(value)
        return string.freeze if IDENTIFIER_PATTERN.match?(string)

        raise InputError.new("hub.mail.mailbox.#{field}.invalid", "#{field} must be a stable identifier")
      rescue TypeError
        raise InputError.new("hub.mail.mailbox.#{field}.invalid", "#{field} must be a stable identifier")
      end

      def required_text(value, field, maximum)
        string = String(value).strip
        return string.freeze if string.length.between?(1, maximum)

        raise InputError.new("hub.mail.mailbox.#{field}.invalid", "#{field} must be nonblank")
      rescue TypeError
        raise InputError.new("hub.mail.mailbox.#{field}.invalid", "#{field} must be nonblank")
      end

      def required_boolean(value, field)
        return value if value == true || value == false

        raise InputError.new("hub.mail.mailbox.#{field}.invalid", "#{field} must be boolean")
      end
    end
  end
end
