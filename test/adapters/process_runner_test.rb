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

  def test_starts_child_without_parent_bundler_activation_and_keeps_explicit_worker_environment
    command = [RbConfig.ruby, "-e", <<~'RUBY']
      values = [ENV["BUNDLE_GEMFILE"], ENV["BUNDLE_BIN_PATH"], ENV["WORKER_MARKER"]]
      STDOUT.write(values.map(&:to_s).join("|"))
    RUBY
    runner = PrismHub::Adapters::ProcessRunner.new(
      command: command,
      environment: {"WORKER_MARKER" => "worker"},
      timeout_seconds: 2
    )

    result = runner.call("")

    assert_equal 0, result.exit_status
    assert_equal "||worker", result.stdout
  end
end
