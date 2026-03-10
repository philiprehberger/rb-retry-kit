# frozen_string_literal: true

module Philiprehberger
  module RetryKit
    # Executes a block with configurable retry logic, backoff, and optional circuit breaker.
    class Executor
      # @param max_attempts [Integer] maximum number of attempts (including the first)
      # @param backoff [Symbol] backoff strategy — :exponential, :linear, or :constant
      # @param base_delay [Numeric] base delay in seconds for backoff calculation
      # @param max_delay [Numeric] maximum delay cap in seconds
      # @param jitter [Symbol] jitter mode — :full, :equal, or :none
      # @param on [Array<Class>] exception classes to retry on (default: StandardError)
      # @param circuit_breaker [CircuitBreaker, nil] optional circuit breaker instance
      # @param on_retry [Proc, nil] callback invoked before each retry with (exception, attempt, delay)
      def initialize(
        max_attempts: 3,
        backoff: :exponential,
        base_delay: 0.5,
        max_delay: 30,
        jitter: :full,
        on: [StandardError],
        circuit_breaker: nil,
        on_retry: nil
      )
        @max_attempts = max_attempts
        @backoff = backoff
        @base_delay = base_delay
        @max_delay = max_delay
        @jitter = jitter
        @retryable_errors = Array(on)
        @circuit_breaker = circuit_breaker
        @on_retry = on_retry
      end

      # Execute the block with retry logic.
      #
      # @yield the block to execute
      # @return the block's return value
      # @raise the last exception if all attempts are exhausted
      def call(&block)
        raise ArgumentError, "Block required" unless block

        attempt = 0

        begin
          attempt += 1

          if @circuit_breaker
            @circuit_breaker.call(&block)
          else
            block.call
          end
        rescue CircuitBreaker::OpenError
          raise
        rescue *@retryable_errors => e
          raise e if attempt >= @max_attempts

          delay = compute_delay(attempt - 1)
          @on_retry&.call(e, attempt, delay)
          sleep(delay)
          retry
        end
      end

      private

      def compute_delay(attempt)
        raw = case @backoff
              when :exponential
                Backoff.exponential(attempt, base_delay: @base_delay, max_delay: @max_delay)
              when :linear
                Backoff.linear(attempt, base_delay: @base_delay, max_delay: @max_delay)
              when :constant
                Backoff.constant(attempt, delay: @base_delay)
              else
                raise ArgumentError, "Unknown backoff strategy: #{@backoff}"
              end

        Backoff.jitter(raw, mode: @jitter)
      end
    end
  end
end
