# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Domain
    class ProviderSubject
      PROVIDER_PATTERN = /\A[a-z][a-z0-9._-]{0,63}\z/
      SCOPE_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\z/
      MAX_SUBJECT_ID_LENGTH = 512

      attr_reader :provider, :provider_scope, :subject_id

      def initialize(provider:, provider_scope:, subject_id:)
        @provider = normalized_reference(provider, "provider", PROVIDER_PATTERN)
        @provider_scope = normalized_reference(provider_scope, "provider_scope", SCOPE_PATTERN)
        @subject_id = normalized_subject_id(subject_id)
        freeze
      end

      def ==(other)
        other.is_a?(self.class) &&
          provider == other.provider &&
          provider_scope == other.provider_scope &&
          subject_id == other.subject_id
      end
      alias eql? ==

      def hash
        [provider, provider_scope, subject_id].hash
      end

      def inspect
        "#<#{self.class} provider=#{provider.inspect} provider_scope=#{provider_scope.inspect} subject_id=[redacted]>"
      end

      private

      def normalized_reference(value, field, pattern)
        string = String(value)
        return string.freeze if pattern.match?(string)

        raise InputError.new(
          "hub.provider_subject.#{field}.invalid",
          "#{field} is not a valid provider reference"
        )
      end

      def normalized_subject_id(value)
        string = String(value)
        if !string.empty? && string.length <= MAX_SUBJECT_ID_LENGTH && !string.match?(/[[:cntrl:]]/)
          return string.freeze
        end

        raise InputError.new(
          "hub.provider_subject.subject_id.invalid",
          "subject_id must be a non-empty opaque provider identifier"
        )
      end
    end
  end
end
