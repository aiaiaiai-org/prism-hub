# © 2026 aiaiaiai · aiaiaiai.org

require "minitest/autorun"
require "rack/mock"
require "rbconfig"
require "stringio"

require_relative "../lib/prism_hub"

module PrismHubTestSupport
  class FakeExecutionGateway < PrismHub::Ports::ExecutionGateway
    attr_reader :envelopes

    def initialize(response: nil)
      @envelopes = []
      @response = response
    end

    def execute(envelope)
      @envelopes << envelope
      @response || {
        "protocol_version" => "prism-execution.v1",
        "request_id" => envelope.fetch("request_id"),
        "status" => "ok",
        "result" => {"type" => "execution", "data" => {"outcomes" => []}}
      }
    end
  end

  class FixedRequestIdFactory
    def initialize(value = "request-test-1")
      @value = value
    end

    def call
      @value
    end
  end

  module_function

  def channels
    PrismHub::Adapters::EnvironmentChannelRepository.new(
      JSON.generate(
        [
          {
            "id" => "personal-threads",
            "label" => "Personal Threads",
            "provider_id" => "meta.threads",
            "channel_ref" => "0x0sky",
            "credential_ref" => "threads.personal"
          }
        ]
      )
    )
  end

  def publication_hash
    {
      "dispatch_policy" => "require_all_valid",
      "variants" => [
        {
          "id" => "personal-post",
          "locale" => "uk-UA",
          "voice_profile" => "0x0sky.uk_SP",
          "format" => "post",
          "body" => {"text" => "привіт із Prism"},
          "provenance" => {"kind" => "human"}
        }
      ],
      "targets" => [
        {
          "id" => "threads-post",
          "channel_id" => "personal-threads",
          "selection" => {"mode" => "exact", "variant_id" => "personal-post"}
        }
      ]
    }
  end
end
