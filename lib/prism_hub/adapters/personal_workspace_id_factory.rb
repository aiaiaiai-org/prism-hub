# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class PersonalWorkspaceIdFactory
      def call(public_user_id)
        canonical = Domain::PublicUserId.new(public_user_id).to_s
        "personal-#{Digest::SHA256.hexdigest(canonical).slice(0, 32)}"
      end
    end
  end
end
