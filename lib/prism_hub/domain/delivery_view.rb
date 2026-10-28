# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    # How a delivery keeps a message current instead of adding one: replace a message sent
    # earlier, remove the ones it supersedes, arrive without a sound, be pinned above the chat
    # when sent anew. The bot is a view and acts on it; the hub decides it.
    #
    # `slot` and `revision` name what the delivery is for (`board` or `status`, and which
    # version), so the message id the bot answers with can be recorded against it.
    class DeliveryView
      SLOTS = %w[board status].freeze
      MAX_DELETES = 10

      attr_reader :edit_message_id, :delete_message_ids, :silent, :pin, :slot, :revision

      def self.from_h(value)
        return nil if value.nil?
        raise invalid("delivery view must be an object") unless value.is_a?(Hash)

        new(
          edit_message_id: value["edit_message_id"],
          delete_message_ids: value.fetch("delete_message_ids", []),
          silent: value.fetch("silent", false),
          pin: value.fetch("pin", false),
          slot: value["slot"],
          revision: value["revision"]
        )
      end

      def self.invalid(message)
        InputError.new("hub.delivery_request.view.invalid", message)
      end

      def initialize(edit_message_id: nil, delete_message_ids: [], silent: false, pin: false, slot: nil, revision: nil)
        @edit_message_id = optional_message_id(edit_message_id)
        @delete_message_ids = message_ids(delete_message_ids)
        @silent = boolean(silent, "silent")
        @pin = boolean(pin, "pin")
        @slot = slot_value(slot)
        @revision = revision_value(revision)
        freeze
      end

      def to_h
        {
          "edit_message_id" => edit_message_id,
          "delete_message_ids" => delete_message_ids,
          "silent" => silent,
          "pin" => pin,
          "slot" => slot,
          "revision" => revision
        }.freeze
      end

      # The fields the bot's delivery endpoint reads; absent ones are left out.
      def to_bot
        body = {}
        body["edit_message_id"] = edit_message_id if edit_message_id
        body["delete_message_ids"] = delete_message_ids unless delete_message_ids.empty?
        body["silent"] = true if silent
        body["pin"] = true if pin
        body
      end

      private

      def optional_message_id(value)
        return nil if value.nil?
        return value if value.is_a?(Integer) && value.positive?

        raise self.class.invalid("edit_message_id must be a positive integer")
      end

      def message_ids(value)
        valid = value.is_a?(Array) && value.length <= MAX_DELETES && value.all? { |id| id.is_a?(Integer) && id.positive? }
        return value.dup.freeze if valid

        raise self.class.invalid("delete_message_ids must be at most #{MAX_DELETES} positive integers")
      end

      def boolean(value, name)
        return value if [true, false].include?(value)

        raise self.class.invalid("#{name} must be true or false")
      end

      def slot_value(value)
        return nil if value.nil?
        return value.dup.freeze if SLOTS.include?(value)

        raise self.class.invalid("slot must be one of #{SLOTS.join(", ")}")
      end

      def revision_value(value)
        return nil if value.nil? && slot.nil?
        return value if value.is_a?(Integer) && value.positive? && slot

        raise self.class.invalid("a slot needs a positive revision, and a revision needs a slot")
      end
    end
  end
end
