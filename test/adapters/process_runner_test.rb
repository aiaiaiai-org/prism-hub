# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ProcessRunnerTest < Minitest::Test
  def test_passes_input_without_a_shell
    runner = PrismHub::Adapters::ProcessRunner.new(
      command: [RbConfig.ruby, "-e", "STDOUT.write(STDIN.read)"],
      timeout_seconds: 2
    )

    result = runner.call("literal $HOME `date`")

    assert_equal 0, result.exit_status
    assert_equal "literal $HOME `date`", result.stdout
    refute result.timed_out
  end

  def test_starts_child_from_unbundled_environment_and_keeps_explicit_worker_environment
    original_bundle_gemfile = ENV["BUNDLE_GEMFILE"]
    ENV["BUNDLE_GEMFILE"] = "/tmp/prism-hub-parent/Gemfile"

    unbundled_environment = {
      "PATH" => ENV.fetch("PATH"),
      "HOME" => ENV.fetch("HOME", "/tmp")
    }
    command = [RbConfig.ruby, "-e", <<~'RUBY']
      STDOUT.write([ENV["BUNDLE_GEMFILE"], ENV["WORKER_MARKER"]].map(&:to_s).join("|"))
    RUBY
    runner = PrismHub::Adapters::ProcessRunner.new(
      command: command,
      environment: {"WORKER_MARKER" => "worker"},
      timeout_seconds: 2
    )

    result = Bundler.stub(:unbundled_env, unbundled_environment) { runner.call("") }

    assert_equal 0, result.exit_status
    assert_equal "|worker", result.stdout
  ensure
    if original_bundle_gemfile
      ENV["BUNDLE_GEMFILE"] = original_bundle_gemfile
    else
      ENV.delete("BUNDLE_GEMFILE")
    end
  end
end
