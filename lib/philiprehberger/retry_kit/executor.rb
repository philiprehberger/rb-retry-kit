# frozen_string_literal: true

module Philiprehberger
  module RetryKit
    class Executor
      VALID_BACKOFFS = %i[exponential linear constant].freeze
      VALID_JITTERS = %i[full equal none decorrelated].freeze

      attr_reader :last_attempts, :last_total_delay

      def initialize(**options)
        assign_options(options)
        validate_options!
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
        check_deadline!
        result, duration, error = timed_attempt(&)
        @on_attempt&.call(attempt + 1, duration, error)

        unless error
          @on_success&.call(@last_attempts, @last_total_delay, result)
          return result
        end

        handle_failure(error, attempt, &)
      end

      def timed_attempt(&)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = execute_attempt(&)
        [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, nil]
      rescue CircuitBreaker::OpenError, TotalTimeoutError, DeadlineExceededError
        raise
      rescue *@retryable_errors => e
        [nil, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, e]
      end

      def handle_failure(error, attempt, &)
        if should_stop?(error, attempt)
          @on_giveup&.call(error, attempt + 1)
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
        delay = clamp_delay(compute_delay(attempt))
        @last_total_delay += delay
        @on_retry&.call(error, attempt + 1, delay)
        sleep(delay)
        attempt_with_retries(attempt + 1, &)
      end

      # Cap the computed backoff delay to whatever time budget remains so a
      # long backoff never sleeps past +total_timeout+/+deadline+. Raises the
      # appropriate error immediately when the budget is already exhausted
      # rather than sleeping.
      def clamp_delay(delay)
        check_total_timeout!
        check_deadline!

        [delay, remaining_timeout, remaining_deadline].compact.min
      end

      def remaining_timeout
        return nil unless @start_time

        @total_timeout - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time)
      end

      def remaining_deadline
        return nil unless @deadline

        @deadline - Time.now
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
        @on_success = options[:on_success]
        @on_giveup = options[:on_giveup]
        @budget = options[:budget]
        @deadline = options[:deadline]
      end

      # Fail fast on invalid configuration so misconfigured retries surface at
      # construction time instead of silently succeeding or misbehaving later.
      def validate_options!
        unless VALID_BACKOFFS.include?(@backoff)
          raise ArgumentError, "Unknown backoff strategy: #{@backoff.inspect}. Use :exponential, :linear, or :constant"
        end
        unless VALID_JITTERS.include?(@jitter)
          raise ArgumentError, "Unknown jitter mode: #{@jitter.inspect}. Use :full, :equal, :none, or :decorrelated"
        end

        validate_numeric_options!
      end

      def validate_numeric_options!
        raise ArgumentError, "max_attempts must be >= 1 (got #{@max_attempts})" if @max_attempts < 1
        raise ArgumentError, "base_delay must be >= 0 (got #{@base_delay})" if @base_delay.negative?
        return unless @max_delay < @base_delay

        raise ArgumentError, "max_delay (#{@max_delay}) must be >= base_delay (#{@base_delay})"
      end

      def check_total_timeout!
        return unless @start_time

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
        return unless elapsed >= @total_timeout

        raise TotalTimeoutError,
              "Total timeout of #{@total_timeout}s exceeded (#{elapsed.round(2)}s elapsed)"
      end

      def check_deadline!
        return unless @deadline
        return if Time.now < @deadline

        raise DeadlineExceededError,
              "Deadline #{@deadline.iso8601} exceeded at #{Time.now.iso8601}"
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
