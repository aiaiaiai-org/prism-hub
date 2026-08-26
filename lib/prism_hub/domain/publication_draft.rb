# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class PublicationDraft
      DISPATCH_POLICIES = %w[require_all_valid independent].freeze
      TOP_LEVEL_KEYS = %w[dispatch_policy variants targets].freeze
      TARGET_KEYS = %w[channel_id id selection].freeze
      VARIANT_KEYS = %w[audience body format id locale provenance voice_profile].freeze
      REFERENCE_PATTERN = Channel::REFERENCE_PATTERN

      class Target
        attr_reader :id, :channel_id, :selection

        def initialize(id:, channel_id:, selection:)
          @id = PublicationDraft.reference(id, "target.id")
          @channel_id = PublicationDraft.reference(channel_id, "target.channel_id")
          @selection = PublicationDraft.selection(selection)
          freeze
        end
      end

      attr_reader :dispatch_policy, :variants, :targets

      def self.from_hash(value)
        object = string_keyed_hash(value, "publication")
        reject_unknown_keys(object, TOP_LEVEL_KEYS, "publication")

        new(
          dispatch_policy: object.fetch("dispatch_policy", "require_all_valid"),
          variants: object.fetch("variants") { missing!("publication.variants") },
          targets: object.fetch("targets") { missing!("publication.targets") }
        )
      end

      def initialize(dispatch_policy:, variants:, targets:)
        @dispatch_policy = validate_dispatch_policy(dispatch_policy)
        @variants = validate_variants(variants)
        @targets = validate_targets(targets)
        freeze
      end

      def prism_payload(idempotency_key:, channels:)
        {
          "idempotency_key" => idempotency_key,
          "dispatch_policy" => dispatch_policy,
          "variants" => variants,
          "targets" => targets.map do |target|
            channel = channels[target.channel_id]
            unless channel
              raise UnknownChannelError.new(
                "hub.channel.not_found",
                "the requested channel is not configured",
                details: {"channel_id" => target.channel_id}
              )
            end
            channel.prism_target(target_id: target.id, selection: target.selection)
          end
        }
      end

      class << self
        def reference(value, field)
          string = String(value)
          return string.freeze if REFERENCE_PATTERN.match?(string)

          raise InputError.new(
            "hub.publication.reference.invalid",
            "#{field} must be a non-empty stable reference"
          )
        end

        def selection(value)
          object = string_keyed_hash(value, "target.selection")
          mode = object["mode"]

          case mode
          when "exact"
            reject_unknown_keys(object, %w[mode variant_id], "target.selection")
            {
              "mode" => "exact",
              "variant_id" => reference(
                object.fetch("variant_id") { missing!("target.selection.variant_id") },
                "target.selection.variant_id"
              )
            }.freeze
          when "ordered"
            reject_unknown_keys(object, %w[mode variant_ids], "target.selection")
            variant_ids = object.fetch("variant_ids") do
              missing!("target.selection.variant_ids")
            end
            unless variant_ids.is_a?(Array) && variant_ids.any?
              raise InputError.new(
                "hub.publication.selection.invalid",
                "ordered selection requires at least one variant_id"
              )
            end
            normalized = variant_ids.map { |id| reference(id, "target.selection.variant_ids") }
            if normalized.uniq.length != normalized.length
              raise InputError.new(
                "hub.publication.selection.duplicate",
                "ordered selection variant_ids must be unique"
              )
            end
            {"mode" => "ordered", "variant_ids" => normalized.freeze}.freeze
          else
            raise InputError.new(
              "hub.publication.selection.invalid",
              "selection mode must be exact or ordered"
            )
          end
        end

        def string_keyed_hash(value, field)
          return value if value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }

          raise InputError.new(
            "hub.publication.object.invalid",
            "#{field} must be a JSON object"
          )
        end

        def reject_unknown_keys(object, allowed, field)
          unknown = object.keys - allowed
          return if unknown.empty?

          raise InputError.new(
            "hub.publication.field.unknown",
            "#{field} contains unsupported fields",
            details: {"fields" => unknown.sort}
          )
        end

        def missing!(field)
          raise InputError.new(
            "hub.publication.field.required",
            "#{field} is required"
          )
        end
      end

      private

      def validate_dispatch_policy(value)
        string = String(value)
        return string.freeze if DISPATCH_POLICIES.include?(string)

        raise InputError.new(
          "hub.publication.dispatch_policy.invalid",
          "dispatch_policy must be require_all_valid or independent"
        )
      end

      def validate_variants(value)
        unless value.is_a?(Array) && value.any?
          raise InputError.new(
            "hub.publication.variants.empty",
            "at least one content variant is required"
          )
        end

        normalized = deep_copy(value)
        unless normalized.all? { |variant| variant.is_a?(Hash) && variant["id"].is_a?(String) }
          raise InputError.new(
            "hub.publication.variant.invalid",
            "every variant must be a JSON object with an id"
          )
        end
        normalized.each do |variant|
          self.class.reject_unknown_keys(variant, VARIANT_KEYS, "variant")
        end
        ensure_unique!(normalized.map { |variant| variant["id"] }, "variant")
        deep_freeze(normalized)
      end

      def validate_targets(value)
        unless value.is_a?(Array) && value.any?
          raise InputError.new(
            "hub.publication.targets.empty",
            "at least one publication target is required"
          )
        end

        normalized = value.map do |target|
          object = self.class.string_keyed_hash(target, "target")
          self.class.reject_unknown_keys(object, TARGET_KEYS, "target")
          Target.new(
            id: object.fetch("id") { self.class.missing!("target.id") },
            channel_id: object.fetch("channel_id") { self.class.missing!("target.channel_id") },
            selection: object.fetch("selection") { self.class.missing!("target.selection") }
          )
        end
        ensure_unique!(normalized.map(&:id), "target")
        normalized.freeze
      end

      def ensure_unique!(values, subject)
        return if values.uniq.length == values.length

        raise InputError.new(
          "hub.publication.#{subject}_id.duplicate",
          "#{subject} ids must be unique"
        )
      end

      def deep_copy(value)
        JSON.parse(JSON.generate(value))
      end

      def deep_freeze(value)
        case value
        when Array
          value.each { |item| deep_freeze(item) }
        when Hash
          value.each do |key, item|
            key.freeze
            deep_freeze(item)
          end
        else
          value.freeze
        end
        value.freeze
      end
    end
  end
end
