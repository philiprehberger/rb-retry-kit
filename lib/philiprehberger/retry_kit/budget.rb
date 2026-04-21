# frozen_string_literal: true

module Philiprehberger
  module RetryKit
    # Thread-safe sliding window retry budget to prevent retry storms.
    #
    # Multiple executors can share a single budget instance. When the budget
    # is exhausted, retries are skipped and the error is raised immediately.
    class Budget
      # Raised when the retry budget is exhausted.
      class ExhaustedError < Error; end

      # @param max_retries [Integer] maximum number of retries allowed in the window
      # @param window [Numeric] sliding window duration in seconds
      def initialize(max_retries:, window:)
        @max_retries = max_retries
        @window = window
        @timestamps = []
        @mutex = Mutex.new
      end

      # Try to consume one retry from the budget.
      #
      # @return [Boolean] true if a retry was consumed, false if budget is exhausted
      def acquire
        @mutex.synchronize do
          prune
          return false if @timestamps.length >= @max_retries

          @timestamps << now
          true
        end
      end

      # Returns the number of remaining retries in the current window.
      #
      # @return [Integer]
      def remaining
        @mutex.synchronize do
          prune
          @max_retries - @timestamps.length
        end
      end

      # Returns whether the budget is exhausted.
      #
      # @return [Boolean]
      def exhausted?
        remaining <= 0
      end

      # Clear all recorded retries. Useful in tests and when manually
      # recovering from a retry storm.
      #
      # @return [self]
      def reset
        @mutex.synchronize { @timestamps.clear }
        self
      end

      private

      def prune
        cutoff = now - @window
        @timestamps.reject! { |t| t < cutoff }
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
