# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class MailDigestSchedulerTest < Minitest::Test
  def test_run_once_uses_a_fixed_window_ending_at_current_time
    calls = []
    now = Time.utc(2026, 9, 14, 5)
    scheduler = PrismHub::UseCases::MailDigestScheduler.new(
      command: ["bin/prism-hub-enqueue-mail-digest"],
      interval_seconds: 3600,
      window_seconds: 1800,
      clock: -> { now },
      runner: ->(command, env) { calls << [command, env] }
    )

    scheduler.run_once

    assert_equal ["bin/prism-hub-enqueue-mail-digest"], calls.first[0]
    assert_equal "2026-09-14T04:30:00Z", calls.first[1].fetch("PRISM_MAIL_SINCE")
    assert_equal "2026-09-14T05:00:00Z", calls.first[1].fetch("PRISM_MAIL_BEFORE")
  end

  def test_rejects_non_positive_intervals
    error = assert_raises(PrismHub::ConfigurationError) do
      PrismHub::UseCases::MailDigestScheduler.new(
        command: ["bin/prism-hub-enqueue-mail-digest"],
        interval_seconds: 0,
        window_seconds: 60
      )
    end

    assert_equal "hub.mail.digest.scheduler.interval.invalid", error.code
  end
end
