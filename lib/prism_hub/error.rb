# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  class Error < StandardError
    attr_reader :code, :details

    def initialize(code, message, details: nil)
      super(message)
      @code = code
      @details = details
    end
  end

  class InputError < Error; end
  class UnknownChannelError < Error; end
  class ExecutionUnavailableError < Error; end
  class ConfigurationError < Error; end
  class CredentialConflictError < Error; end
  class CredentialNotFoundError < Error; end
end
