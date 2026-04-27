# frozen_string_literal: true

require 'time'

module Philiprehberger
  module RetryKit
    class Error < StandardError; end

    # Raised when total elapsed time across all retries exceeds the limit.
    class TotalTimeoutError < Error; end

    # Raised when an absolute wall-clock deadline is reached before the
    # block succeeds. See the `deadline:` option on Executor.
    class DeadlineExceededError < Error; end

    # Execute a block with retry logic.
    #
    # @param options [Hash] options passed to Executor.new
    # @yield the block to execute
    # @return the block's return value
    # @see Executor#initialize for available options
    def self.run(**options, &)
      Executor.new(**options).call(&)
    end

    # Named retry presets — each value is a Hash of keyword arguments
    # accepted by {.run}. Use {.with_preset} to apply one with optional
    # per-call overrides.
    #
    # Available presets:
    # - +:aggressive+ — small +max_attempts+, short delays, full jitter,
    #   exponential backoff. For low-latency calls where giving up fast
    #   is preferable to waiting.
    # - +:conservative+ — larger +max_attempts+, longer delays, full
    #   jitter, exponential backoff. For background work where success
    #   matters more than speed.
    # - +:network+ — middle ground tuned for transient HTTP errors;
    #   exponential backoff with full jitter.
    PRESETS = {
      aggressive: {
        max_attempts: 3,
        backoff: :exponential,
        base_delay: 0.1,
        max_delay: 1.0,
        jitter: :full
      }.freeze,
      conservative: {
        max_attempts: 6,
        backoff: :exponential,
        base_delay: 1.0,
        max_delay: 60.0,
        jitter: :full
      }.freeze,
      network: {
        max_attempts: 4,
        backoff: :exponential,
        base_delay: 0.5,
        max_delay: 30.0,
        jitter: :full
      }.freeze
    }.freeze

    # Execute a block with retry logic using a named preset from {PRESETS}.
    #
    # The preset's keyword arguments are merged with +overrides+ (overrides
    # win on conflict) and forwarded to {.run}.
    #
    # @param name [Symbol] the preset name (must be a key of {PRESETS})
    # @param overrides [Hash] keyword arguments that override preset values
    # @yield the block to execute
    # @return the block's return value
    # @raise [ArgumentError] if +name+ is not a known preset
    # @see PRESETS
    # @see .run
    def self.with_preset(name, **overrides, &)
      preset = PRESETS[name]
      raise ArgumentError, "Unknown preset: #{name}" unless preset

      run(**preset, **overrides, &)
    end
  end
end

require_relative 'retry_kit/version'
require_relative 'retry_kit/backoff'
require_relative 'retry_kit/budget'
require_relative 'retry_kit/circuit_breaker'
require_relative 'retry_kit/executor'
