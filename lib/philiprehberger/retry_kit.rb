# frozen_string_literal: true

require_relative "retry_kit/version"
require_relative "retry_kit/backoff"
require_relative "retry_kit/circuit_breaker"
require_relative "retry_kit/executor"

module Philiprehberger
  module RetryKit
    class Error < StandardError; end

    # Execute a block with retry logic.
    #
    # @param options [Hash] options passed to Executor.new
    # @yield the block to execute
    # @return the block's return value
    # @see Executor#initialize for available options
    def self.run(**options, &block)
      Executor.new(**options).call(&block)
    end
  end
end
