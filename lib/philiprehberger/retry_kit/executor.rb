# frozen_string_literal: true

module Philiprehberger
  module RetryKit
    class Executor
      attr_reader :last_attempts, :last_total_delay

      def initialize(**options)
        assign_options(options)
        @last_attempts = 0
        @last_total_delay = 0.0
      end

      def call(&block)
        raise ArgumentError, 'Block required' unless block

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
        @circuit_breaker ? @circuit_breaker.call(&) : yield
      end

      def compute_delay(attempt)
        return compute_decorrelated_delay if @jitter == :decorrelated

        Backoff.jitter(backoff_delay(attempt), mode: @jitter)
      end

      def compute_decorrelated_delay
        delay = Backoff.decorrelated(@last_decorrelated_delay, base_delay: @base_delay, max_delay: @max_delay)
        @last_decorrelated_delay = delay
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
