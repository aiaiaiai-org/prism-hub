# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ClientCredentialLifecycleTest < Minitest::Test
  class FakeRepository < PrismHub::Ports::ClientCredentialRepository
    attr_reader :issued, :rotated, :revoked

    def issue(**arguments)
      @issued = arguments
      "credential-1"
    end

    def rotate(**arguments)
      @rotated = arguments
      "credential-2"
    end

    def revoke(**arguments)
      @revoked = arguments
      arguments.fetch(:credential_id)
    end

    def authenticate(**)
      nil
    end
  end

  TOKEN = "prism_client_v1_#{'d' * 43}".freeze
  NOW = Time.utc(2026, 8, 27, 9, 47, 0)

  def test_issue_returns_secret_once_without_exposing_it_in_inspect
    repository = FakeRepository.new
    issued = PrismHub::UseCases::IssueClientCredential.new(
      repository: repository,
      token_generator: -> { TOKEN }
    ).call(
      workspace_id: "personal",
      principal_id: "telegram-personal",
      bot_instance_id: "prisma-telegram",
      capabilities: ["channels:read"],
      channel_ids: ["personal-threads"]
    )

    assert_equal TOKEN, issued.token
    assert_equal TOKEN, repository.issued.fetch(:token)
    refute_includes issued.inspect, TOKEN
    assert_includes issued.inspect, "[REDACTED]"
  end

  def test_rotate_and_revoke_use_an_injected_clock
    repository = FakeRepository.new
    rotated = PrismHub::UseCases::RotateClientCredential.new(
      repository: repository,
      token_generator: -> { TOKEN },
      clock: -> { NOW }
    ).call(credential_id: "credential-1")

    assert_equal "credential-2", rotated.id
    assert_equal NOW, repository.rotated.fetch(:rotated_at)

    PrismHub::UseCases::RevokeClientCredential.new(
      repository: repository,
      clock: -> { NOW }
    ).call(credential_id: "credential-2")
    assert_equal NOW, repository.revoked.fetch(:revoked_at)
  end
end
