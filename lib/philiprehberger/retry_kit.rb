# frozen_string_literal: true

module Philiprehberger
  module RetryKit
    class Error < StandardError; end

    # Raised when total elapsed time across all retries exceeds the limit.
    class TotalTimeoutError < Error; end

    # Execute a block with retry logic.
    #
    # @param options [Hash] options passed to Executor.new
    # @yield the block to execute
    # @return the block's return value
    # @see Executor#initialize for available options
    def self.run(**options, &)
      Executor.new(**options).call(&)
    end
  end
end

require_relative "retry_kit/version"
require_relative "retry_kit/backoff"
require_relative "retry_kit/budget"
require_relative "retry_kit/circuit_breaker"
require_relative "retry_kit/executor"
