# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    class ProcessRunner
      Result = Struct.new(
        :stdout,
        :stderr,
        :exit_status,
        :timed_out,
        :stdout_too_large,
        :stderr_too_large,
        keyword_init: true
      )

      def initialize(
        command:,
        environment: {},
        timeout_seconds: 10,
        max_stdout_bytes: 1_048_576,
        max_stderr_bytes: 65_536
      )
        @command = command.freeze
        @environment = environment.freeze
        @timeout_seconds = timeout_seconds
        @max_stdout_bytes = max_stdout_bytes
        @max_stderr_bytes = max_stderr_bytes
      end

      def call(input)
        result = nil
        Open3.popen3(@environment, *@command) do |stdin, stdout, stderr, wait_thread|
          writer = Thread.new { write_input(stdin, input) }
          stdout_reader = Thread.new { read_stream(stdout, @max_stdout_bytes) }
          stderr_reader = Thread.new { read_stream(stderr, @max_stderr_bytes) }
          timed_out = wait_thread.join(@timeout_seconds).nil?
          terminate(wait_thread) if timed_out

          writer.join
          stdout_capture = stdout_reader.value
          stderr_capture = stderr_reader.value
          status = wait_thread.value
          result = Result.new(
            stdout: stdout_capture.fetch(:content),
            stderr: stderr_capture.fetch(:content),
            exit_status: status.exitstatus,
            timed_out: timed_out,
            stdout_too_large: stdout_capture.fetch(:too_large),
            stderr_too_large: stderr_capture.fetch(:too_large)
          ).freeze
        end
        result
      rescue SystemCallError => error
        raise ExecutionUnavailableError.new(
          "hub.prism.process.unavailable",
          "Prism runtime process could not be started",
          details: {"system_error" => error.class.name}
        )
      end

      private

      def write_input(io, input)
        io.write(input)
      rescue Errno::EPIPE, IOError
        nil
      ensure
        io.close unless io.closed?
      end

      def read_stream(io, limit)
        content = +""
        too_large = false
        loop do
          chunk = io.readpartial(16_384)
          remaining = limit - content.bytesize
          if remaining.positive?
            content << chunk.byteslice(0, remaining)
          end
          too_large ||= chunk.bytesize > remaining
        end
      rescue EOFError, IOError
        {content: content.freeze, too_large: too_large}.freeze
      end

      def terminate(wait_thread)
        Process.kill("TERM", wait_thread.pid)
        return if wait_thread.join(1)

        Process.kill("KILL", wait_thread.pid)
        wait_thread.join
      rescue Errno::ESRCH, Errno::ECHILD
        wait_thread.join
      end
    end
  end
end
