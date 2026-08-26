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
end
