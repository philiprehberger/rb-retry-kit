# frozen_string_literal: true

module Philiprehberger
  module RetryKit
    # Backoff strategy calculators.
    module Backoff
      module_function

      # Exponential backoff: base_delay * 2^attempt
      #
      # @param attempt [Integer] the current attempt number (0-based)
      # @param base_delay [Numeric] the base delay in seconds
      # @param max_delay [Numeric] the maximum delay cap in seconds
      # @return [Numeric] delay in seconds
      def exponential(attempt, base_delay: 0.5, max_delay: 30)
        delay = base_delay * (2**attempt)
        [delay, max_delay].min
      end

      # Linear backoff: base_delay * (attempt + 1)
      #
      # @param attempt [Integer] the current attempt number (0-based)
      # @param base_delay [Numeric] the base delay in seconds
      # @param max_delay [Numeric] the maximum delay cap in seconds
      # @return [Numeric] delay in seconds
      def linear(attempt, base_delay: 0.5, max_delay: 30)
        delay = base_delay * (attempt + 1)
        [delay, max_delay].min
      end

      # Constant backoff: always the same delay.
      #
      # @param _attempt [Integer] ignored
      # @param delay [Numeric] the constant delay in seconds
      # @return [Numeric] delay in seconds
      def constant(_attempt, delay: 1)
        delay
      end

      # Add jitter to a delay value.
      #
      # @param delay [Numeric] the base delay
      # @param mode [Symbol] jitter mode — :full, :equal, or :none
      # @return [Float] jittered delay
      def jitter(delay, mode: :full)
        case mode
        when :full
          rand * delay
        when :equal
          (delay / 2.0) + (rand * delay / 2.0)
        when :none
          delay.to_f
        else
          raise ArgumentError, "Unknown jitter mode: #{mode}. Use :full, :equal, or :none"
        end
      end
    end
  end
end
