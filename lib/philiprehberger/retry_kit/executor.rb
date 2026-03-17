# frozen_string_literal: true

module Philiprehberger
  module RetryKit
    # Executes a block with configurable retry logic, backoff, and optional circuit breaker.
    class Executor
      # Number of attempts in the last execution.
      # @return [Integer]
      attr_reader :last_attempts

      # Total delay (seconds) spent sleeping across retries in the last execution.
      # @return [Float]
      attr_reader :last_total_delay

      # @param options [Hash] retry configuration options
      # @option options [Integer] :max_attempts (3) maximum number of attempts
      # @option options [Symbol] :backoff (:exponential) backoff strategy
      # @option options [Numeric] :base_delay (0.5) base delay in seconds
      # @option options [Numeric] :max_delay (30) maximum delay cap in seconds
      # @option options [Symbol] :jitter (:full) jitter mode
      # @option options [Array<Class>] :on ([StandardError]) exception classes to retry on
      # @option options [CircuitBreaker, nil] :circuit_breaker (nil) optional circuit breaker
      # @option options [Proc, nil] :on_retry (nil) callback before each retry
      # @option options [Numeric, nil] :total_timeout (nil) max total seconds across all attempts
      # @option options [Proc, nil] :fallback (nil) handler called with last error when all retries exhausted
      # @option options [Proc, nil] :retry_if (nil) predicate receiving (error, attempt) to decide whether to retry
      # @option options [Proc, nil] :on_attempt (nil) callback after each attempt: (attempt, duration, error)
      # @option options [Budget, nil] :budget (nil) shared retry budget
      def initialize(**options)
        assign_options(options)
        @last_attempts = 0
        @last_total_delay = 0.0
      end

      # Execute the block with retry logic.
      #
      # @yield the block to execute
      # @return the block's return value
      # @raise the last exception if all attempts are exhausted
      def call(&block)
        raise ArgumentError, "Block required" unless block

        @last_attempts = 0
        @last_total_delay = 0.0
        @last_decorrelated_delay = @base_delay
        @start_time = @total_timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : nil

        attempt_with_retries(0, &block)
      end

      private

      def attempt_with_retries(attempt, &)
        @last_attempts = attempt + 1
        check_total_timeout!
        result, duration, error = timed_attempt(&)
        @on_attempt&.call(attempt + 1, duration, error)
        return result unless error

        handle_failure(error, attempt, &)
      end

      def timed_attempt(&)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = execute_attempt(&)
        [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, nil]
      rescue CircuitBreaker::OpenError, TotalTimeoutError
        raise
      rescue *@retryable_errors => e
        [nil, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, e]
      end

      def handle_failure(error, attempt, &)
        if should_stop?(error, attempt)
          return @fallback.call(error) if @fallback

          raise error
        end

        wait_and_retry(error, attempt, &)
      end

      def should_stop?(error, attempt)
        return true if attempt + 1 >= @max_attempts
        return true if @retry_if && !@retry_if.call(error, attempt + 1)
        return true if @budget && !@budget.acquire

        false
      end

      def wait_and_retry(error, attempt, &)
        delay = compute_delay(attempt)
        @last_total_delay += delay
        @on_retry&.call(error, attempt + 1, delay)
        sleep(delay)
        attempt_with_retries(attempt + 1, &)
      end

      def assign_options(options)
        assign_core_options(options)
        assign_callback_options(options)
      end

      def assign_core_options(options)
        @max_attempts = options.fetch(:max_attempts, 3)
        @backoff = options.fetch(:backoff, :exponential)
        @base_delay = options.fetch(:base_delay, 0.5)
        @max_delay = options.fetch(:max_delay, 30)
        @jitter = options.fetch(:jitter, :full)
        @retryable_errors = Array(options.fetch(:on, [StandardError]))
      end

      def assign_callback_options(options)
        @circuit_breaker = options[:circuit_breaker]
        @on_retry = options[:on_retry]
        @total_timeout = options[:total_timeout]
        @fallback = options[:fallback]
        @retry_if = options[:retry_if]
        @on_attempt = options[:on_attempt]
        @budget = options[:budget]
      end

      def check_total_timeout!
        return unless @start_time

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
        return unless elapsed >= @total_timeout

        raise TotalTimeoutError,
              "Total timeout of #{@total_timeout}s exceeded (#{elapsed.round(2)}s elapsed)"
      end

      def execute_attempt(&)
        if @circuit_breaker
          @circuit_breaker.call(&)
        else
          yield
        end
      end

      def compute_delay(attempt)
        if @jitter == :decorrelated
          delay = Backoff.decorrelated(@last_decorrelated_delay, base_delay: @base_delay, max_delay: @max_delay)
          @last_decorrelated_delay = delay
          delay
        else
          raw = backoff_delay(attempt)
          Backoff.jitter(raw, mode: @jitter)
        end
      end

      def backoff_delay(attempt)
        case @backoff
        when :exponential then Backoff.exponential(attempt, base_delay: @base_delay, max_delay: @max_delay)
        when :linear then Backoff.linear(attempt, base_delay: @base_delay, max_delay: @max_delay)
        when :constant then Backoff.constant(attempt, delay: @base_delay)
        else raise ArgumentError, "Unknown backoff strategy: #{@backoff}"
        end
      end
    end
  end
end
