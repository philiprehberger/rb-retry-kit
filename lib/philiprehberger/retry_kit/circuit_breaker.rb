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
      # @param on_state_change [Proc, nil] callback when state changes, receives (old_state, new_state)
      def initialize(failure_threshold: 5, cooldown: 30, on_state_change: nil)
        @failure_threshold = failure_threshold
        @cooldown = cooldown
        @on_state_change = on_state_change
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
        raise ArgumentError, 'Block required' unless block

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
          transition_to(:closed)
          @last_failure_time = nil
        end
      end

      private

      def check_state!
        case @state
        when :open
          unless cooldown_elapsed?
            raise OpenError, "Circuit is open (#{@failure_count} failures, cooldown: #{@cooldown}s)"
          end

          transition_to(:half_open)
        when :half_open
          # Allow one attempt through
        end
      end

      def record_success
        @mutex.synchronize do
          @failure_count = 0
          transition_to(:closed)
          @last_failure_time = nil
        end
      end

      def record_failure
        @mutex.synchronize do
          @failure_count += 1
          @last_failure_time = Time.now

          transition_to(:open) if @failure_count >= @failure_threshold
        end
      end

      def transition_to(new_state)
        old_state = @state
        @state = new_state
        @on_state_change&.call(old_state, new_state) if old_state != new_state
      end

      def cooldown_elapsed?
        @last_failure_time && (Time.now - @last_failure_time) >= @cooldown
      end
    end
  end
end
