# frozen_string_literal: true

module Philiprehberger
  module RetryKit
    # A simple circuit breaker that tracks failures and opens the circuit
    # when a threshold is exceeded, preventing further calls until a
    # cooldown period has elapsed.
    class CircuitBreaker
      # Raised when the circuit is open and a call is attempted.
      class OpenError < Error; end

      STATES = %i[closed open half_open].freeze

      attr_reader :state, :failure_count, :failure_threshold, :cooldown

      # @param failure_threshold [Integer] number of failures before opening
      # @param cooldown [Numeric] seconds to wait before transitioning to half-open
      def initialize(failure_threshold: 5, cooldown: 30)
        @failure_threshold = failure_threshold
        @cooldown = cooldown
        @failure_count = 0
        @state = :closed
        @last_failure_time = nil
        @mutex = Mutex.new
      end

      # Execute a block through the circuit breaker.
      #
      # @yield the block to execute
      # @return the block's return value
      # @raise [OpenError] if the circuit is open
      def call(&block)
        raise ArgumentError, "Block required" unless block

        @mutex.synchronize { check_state! }

        result = block.call
        record_success
        result
      rescue OpenError
        raise
      rescue StandardError => e
        record_failure
        raise e
      end

      # Reset the circuit breaker to closed state.
      def reset
        @mutex.synchronize do
          @failure_count = 0
          @state = :closed
          @last_failure_time = nil
        end
      end

      private

      def check_state!
        case @state
        when :open
          if cooldown_elapsed?
            @state = :half_open
          else
            raise OpenError, "Circuit is open (#{@failure_count} failures, cooldown: #{@cooldown}s)"
          end
        when :half_open
          # Allow one attempt through
        end
      end

      def record_success
        @mutex.synchronize do
          @failure_count = 0
          @state = :closed
          @last_failure_time = nil
        end
      end

      def record_failure
        @mutex.synchronize do
          @failure_count += 1
          @last_failure_time = Time.now

          @state = :open if @failure_count >= @failure_threshold
        end
      end

      def cooldown_elapsed?
        @last_failure_time && (Time.now - @last_failure_time) >= @cooldown
      end
    end
  end
end
