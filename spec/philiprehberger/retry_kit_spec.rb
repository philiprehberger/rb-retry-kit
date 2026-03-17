# frozen_string_literal: true

require "spec_helper"

RSpec.describe Philiprehberger::RetryKit do
  it "has a version number" do
    expect(Philiprehberger::RetryKit::VERSION).not_to be_nil
  end

  describe ".run" do
    it "returns the block result on success" do
      result = described_class.run { 42 }
      expect(result).to eq(42)
    end

    it "retries on failure and succeeds" do
      attempts = 0
      result = described_class.run(max_attempts: 3, backoff: :constant, base_delay: 0, jitter: :none) do
        attempts += 1
        raise StandardError, "fail" if attempts < 3

        "ok"
      end

      expect(result).to eq("ok")
      expect(attempts).to eq(3)
    end

    it "raises after exhausting attempts" do
      expect do
        described_class.run(max_attempts: 2, backoff: :constant, base_delay: 0, jitter: :none) do
          raise StandardError, "always fails"
        end
      end.to raise_error(StandardError, "always fails")
    end

    it "only retries specified error classes" do
      expect do
        described_class.run(max_attempts: 3, on: [ArgumentError], backoff: :constant, base_delay: 0, jitter: :none) do
          raise "wrong type"
        end
      end.to raise_error(RuntimeError, "wrong type")
    end

    it "calls on_retry callback before each retry" do
      retries = []
      callback = ->(error, attempt, delay) { retries << { error: error.message, attempt: attempt, delay: delay } }

      attempts = 0
      described_class.run(max_attempts: 3, backoff: :constant, base_delay: 0, jitter: :none, on_retry: callback) do
        attempts += 1
        raise StandardError, "fail" if attempts < 3

        "ok"
      end

      expect(retries.length).to eq(2)
      expect(retries.first[:attempt]).to eq(1)
      expect(retries.last[:attempt]).to eq(2)
    end

    it "raises TotalTimeoutError when total_timeout is exceeded" do
      executor = Philiprehberger::RetryKit::Executor.new(
        max_attempts: 10, backoff: :constant, base_delay: 0.05, jitter: :none, total_timeout: 0.1
      )

      expect do
        executor.call { raise StandardError, "fail" }
      end.to raise_error(Philiprehberger::RetryKit::TotalTimeoutError)
    end
  end

  describe "execution stats" do
    it "tracks last_attempts and last_total_delay" do
      executor = Philiprehberger::RetryKit::Executor.new(
        max_attempts: 3, backoff: :constant, base_delay: 0, jitter: :none
      )

      attempts = 0
      executor.call do
        attempts += 1
        raise StandardError, "fail" if attempts < 3

        "ok"
      end

      expect(executor.last_attempts).to eq(3)
      expect(executor.last_total_delay).to eq(0.0)
    end

    it "accumulates delay across retries" do
      executor = Philiprehberger::RetryKit::Executor.new(
        max_attempts: 3, backoff: :constant, base_delay: 0.01, jitter: :none
      )

      attempts = 0
      executor.call do
        attempts += 1
        raise StandardError, "fail" if attempts < 3

        "ok"
      end

      expect(executor.last_attempts).to eq(3)
      expect(executor.last_total_delay).to be_within(0.001).of(0.02)
    end
  end

  describe "decorrelated jitter" do
    it "produces delays between base_delay and max_delay" do
      delays = []
      callback = ->(_error, _attempt, delay) { delays << delay }

      attempts = 0
      described_class.run(
        max_attempts: 5,
        backoff: :exponential,
        base_delay: 0.01,
        max_delay: 1,
        jitter: :decorrelated,
        on_retry: callback
      ) do
        attempts += 1
        raise StandardError, "fail" if attempts < 5

        "ok"
      end

      expect(delays.length).to eq(4)
      delays.each do |d|
        expect(d).to be >= 0.01
        expect(d).to be <= 1
      end
    end

    it "caps decorrelated delay at max_delay" do
      # With a very small max_delay, all results should be capped
      delays = []
      callback = ->(_error, _attempt, delay) { delays << delay }

      attempts = 0
      described_class.run(
        max_attempts: 4,
        backoff: :exponential,
        base_delay: 0.01,
        max_delay: 0.02,
        jitter: :decorrelated,
        on_retry: callback
      ) do
        attempts += 1
        raise StandardError, "fail" if attempts < 4

        "ok"
      end

      delays.each do |d|
        expect(d).to be <= 0.02
      end
    end
  end

  describe "fallback handler" do
    it "returns fallback value when all retries are exhausted" do
      result = described_class.run(
        max_attempts: 2,
        backoff: :constant,
        base_delay: 0,
        jitter: :none,
        fallback: ->(_error) { "default" }
      ) do
        raise StandardError, "fail"
      end

      expect(result).to eq("default")
    end

    it "passes the last error to the fallback" do
      received_error = nil
      described_class.run(
        max_attempts: 2,
        backoff: :constant,
        base_delay: 0,
        jitter: :none,
        fallback: ->(error) { received_error = error; nil }
      ) do
        raise StandardError, "specific failure"
      end

      expect(received_error).to be_a(StandardError)
      expect(received_error.message).to eq("specific failure")
    end

    it "does not call fallback on success" do
      fallback_called = false
      result = described_class.run(
        max_attempts: 3,
        fallback: ->(_error) { fallback_called = true; "fallback" }
      ) do
        "success"
      end

      expect(result).to eq("success")
      expect(fallback_called).to be(false)
    end

    it "raises error when no fallback is provided" do
      expect do
        described_class.run(max_attempts: 1, backoff: :constant, base_delay: 0, jitter: :none) do
          raise StandardError, "fail"
        end
      end.to raise_error(StandardError, "fail")
    end
  end

  describe "retry predicate" do
    it "stops retrying when retry_if returns false" do
      attempts = 0
      expect do
        described_class.run(
          max_attempts: 10,
          backoff: :constant,
          base_delay: 0,
          jitter: :none,
          retry_if: ->(_error, attempt) { attempt < 3 }
        ) do
          attempts += 1
          raise StandardError, "fail"
        end
      end.to raise_error(StandardError, "fail")

      expect(attempts).to eq(3)
    end

    it "receives error and attempt number" do
      received = []
      begin
        described_class.run(
          max_attempts: 5,
          backoff: :constant,
          base_delay: 0,
          jitter: :none,
          retry_if: ->(error, attempt) { received << [error.message, attempt]; true }
        ) do
          raise StandardError, "test error"
        end
      rescue StandardError
        nil
      end

      expect(received.length).to eq(4)
      expect(received.first).to eq(["test error", 1])
      expect(received.last).to eq(["test error", 4])
    end

    it "works together with on: exception filter" do
      attempts = 0
      expect do
        described_class.run(
          max_attempts: 5,
          backoff: :constant,
          base_delay: 0,
          jitter: :none,
          on: [ArgumentError],
          retry_if: ->(_error, _attempt) { true }
        ) do
          attempts += 1
          raise RuntimeError, "not retryable"
        end
      end.to raise_error(RuntimeError)

      expect(attempts).to eq(1)
    end

    it "uses fallback when retry_if stops retries early" do
      result = described_class.run(
        max_attempts: 10,
        backoff: :constant,
        base_delay: 0,
        jitter: :none,
        retry_if: ->(_error, attempt) { attempt < 2 },
        fallback: ->(_error) { "fallback value" }
      ) do
        raise StandardError, "fail"
      end

      expect(result).to eq("fallback value")
    end
  end

  describe "per-attempt callback" do
    it "calls on_attempt after each attempt including success" do
      attempt_log = []
      attempts = 0
      described_class.run(
        max_attempts: 3,
        backoff: :constant,
        base_delay: 0,
        jitter: :none,
        on_attempt: ->(attempt, duration, error) { attempt_log << { attempt: attempt, error: error } }
      ) do
        attempts += 1
        raise StandardError, "fail" if attempts < 3

        "ok"
      end

      expect(attempt_log.length).to eq(3)
      expect(attempt_log[0][:attempt]).to eq(1)
      expect(attempt_log[0][:error]).to be_a(StandardError)
      expect(attempt_log[1][:attempt]).to eq(2)
      expect(attempt_log[1][:error]).to be_a(StandardError)
      expect(attempt_log[2][:attempt]).to eq(3)
      expect(attempt_log[2][:error]).to be_nil
    end

    it "provides duration in seconds" do
      durations = []
      described_class.run(
        max_attempts: 2,
        backoff: :constant,
        base_delay: 0,
        jitter: :none,
        on_attempt: ->(_attempt, duration, _error) { durations << duration }
      ) do
        "ok"
      end

      expect(durations.length).to eq(1)
      expect(durations.first).to be_a(Float)
      expect(durations.first).to be >= 0
    end

    it "is called even when all retries are exhausted" do
      attempt_log = []
      begin
        described_class.run(
          max_attempts: 2,
          backoff: :constant,
          base_delay: 0,
          jitter: :none,
          on_attempt: ->(attempt, _duration, error) { attempt_log << { attempt: attempt, error: error&.message } }
        ) do
          raise StandardError, "always fails"
        end
      rescue StandardError
        nil
      end

      expect(attempt_log.length).to eq(2)
      expect(attempt_log.last[:error]).to eq("always fails")
    end
  end

  describe "retry budget" do
    it "limits retries across executors" do
      budget = Philiprehberger::RetryKit::Budget.new(max_retries: 3, window: 60)

      # First executor uses 2 retries
      attempts_a = 0
      begin
        described_class.run(
          max_attempts: 3,
          backoff: :constant,
          base_delay: 0,
          jitter: :none,
          budget: budget
        ) do
          attempts_a += 1
          raise StandardError, "fail"
        end
      rescue StandardError
        nil
      end

      # Second executor should only get 1 retry before budget is exhausted
      attempts_b = 0
      begin
        described_class.run(
          max_attempts: 5,
          backoff: :constant,
          base_delay: 0,
          jitter: :none,
          budget: budget
        ) do
          attempts_b += 1
          raise StandardError, "fail"
        end
      rescue StandardError
        nil
      end

      # Total retries (not counting initial attempts) should be 3
      total_retries = (attempts_a - 1) + (attempts_b - 1)
      expect(total_retries).to eq(3)
    end

    it "raises immediately when budget is exhausted" do
      budget = Philiprehberger::RetryKit::Budget.new(max_retries: 0, window: 60)

      attempts = 0
      expect do
        described_class.run(
          max_attempts: 5,
          backoff: :constant,
          base_delay: 0,
          jitter: :none,
          budget: budget
        ) do
          attempts += 1
          raise StandardError, "fail"
        end
      end.to raise_error(StandardError, "fail")

      expect(attempts).to eq(1)
    end

    it "uses fallback when budget prevents retries" do
      budget = Philiprehberger::RetryKit::Budget.new(max_retries: 0, window: 60)

      result = described_class.run(
        max_attempts: 5,
        backoff: :constant,
        base_delay: 0,
        jitter: :none,
        budget: budget,
        fallback: ->(_error) { "budget fallback" }
      ) do
        raise StandardError, "fail"
      end

      expect(result).to eq("budget fallback")
    end
  end
end

RSpec.describe Philiprehberger::RetryKit::Backoff do
  describe ".exponential" do
    it "doubles the delay each attempt" do
      expect(described_class.exponential(0, base_delay: 1, max_delay: 100)).to eq(1)
      expect(described_class.exponential(1, base_delay: 1, max_delay: 100)).to eq(2)
      expect(described_class.exponential(2, base_delay: 1, max_delay: 100)).to eq(4)
      expect(described_class.exponential(3, base_delay: 1, max_delay: 100)).to eq(8)
    end

    it "caps at max_delay" do
      expect(described_class.exponential(10, base_delay: 1, max_delay: 30)).to eq(30)
    end
  end

  describe ".linear" do
    it "increases delay linearly" do
      expect(described_class.linear(0, base_delay: 1, max_delay: 100)).to eq(1)
      expect(described_class.linear(1, base_delay: 1, max_delay: 100)).to eq(2)
      expect(described_class.linear(2, base_delay: 1, max_delay: 100)).to eq(3)
    end

    it "caps at max_delay" do
      expect(described_class.linear(50, base_delay: 1, max_delay: 10)).to eq(10)
    end
  end

  describe ".constant" do
    it "returns the same delay every time" do
      expect(described_class.constant(0, delay: 5)).to eq(5)
      expect(described_class.constant(99, delay: 5)).to eq(5)
    end
  end

  describe ".jitter" do
    it "returns a value between 0 and delay for :full mode" do
      100.times do
        result = described_class.jitter(10, mode: :full)
        expect(result).to be >= 0
        expect(result).to be < 10
      end
    end

    it "returns a value between delay/2 and delay for :equal mode" do
      100.times do
        result = described_class.jitter(10, mode: :equal)
        expect(result).to be >= 5
        expect(result).to be < 10
      end
    end

    it "returns the exact delay for :none mode" do
      expect(described_class.jitter(10, mode: :none)).to eq(10.0)
    end

    it "raises on unknown mode" do
      expect { described_class.jitter(10, mode: :unknown) }.to raise_error(ArgumentError)
    end
  end

  describe ".decorrelated" do
    it "returns a value between base_delay and max_delay" do
      100.times do
        result = described_class.decorrelated(1.0, base_delay: 0.5, max_delay: 30)
        expect(result).to be >= 0.5
        expect(result).to be <= 30
      end
    end

    it "caps at max_delay" do
      result = described_class.decorrelated(100, base_delay: 0.5, max_delay: 5)
      expect(result).to be <= 5
    end

    it "uses last_delay to scale the upper bound" do
      # With a very small last_delay, results should be small
      results = Array.new(100) { described_class.decorrelated(0.1, base_delay: 0.01, max_delay: 100) }
      expect(results.max).to be <= 0.3
    end
  end
end

RSpec.describe Philiprehberger::RetryKit::Budget do
  describe "#acquire" do
    it "allows retries within the budget" do
      budget = described_class.new(max_retries: 3, window: 60)
      expect(budget.acquire).to be(true)
      expect(budget.acquire).to be(true)
      expect(budget.acquire).to be(true)
    end

    it "rejects retries when budget is exhausted" do
      budget = described_class.new(max_retries: 2, window: 60)
      budget.acquire
      budget.acquire
      expect(budget.acquire).to be(false)
    end
  end

  describe "#remaining" do
    it "returns the remaining retry count" do
      budget = described_class.new(max_retries: 5, window: 60)
      expect(budget.remaining).to eq(5)
      budget.acquire
      expect(budget.remaining).to eq(4)
    end
  end

  describe "#exhausted?" do
    it "returns false when budget has remaining retries" do
      budget = described_class.new(max_retries: 1, window: 60)
      expect(budget.exhausted?).to be(false)
    end

    it "returns true when budget is exhausted" do
      budget = described_class.new(max_retries: 1, window: 60)
      budget.acquire
      expect(budget.exhausted?).to be(true)
    end
  end

  describe "thread safety" do
    it "handles concurrent access without exceeding the budget" do
      budget = described_class.new(max_retries: 100, window: 60)
      acquired = Concurrent::AtomicFixnum.new(0) if defined?(Concurrent)

      threads = Array.new(10) do
        Thread.new do
          50.times do
            acquired_locally = budget.acquire
            # Just count successful acquisitions
            break unless acquired_locally
          end
        end
      end
      threads.each(&:join)

      expect(budget.remaining).to be >= 0
    end
  end
end

RSpec.describe Philiprehberger::RetryKit::CircuitBreaker do
  subject(:breaker) { described_class.new(failure_threshold: 3, cooldown: 0.1) }

  it "starts in closed state" do
    expect(breaker.state).to eq(:closed)
  end

  it "allows calls when closed" do
    result = breaker.call { 42 }
    expect(result).to eq(42)
  end

  it "opens after reaching failure threshold" do
    3.times do
      breaker.call { raise StandardError }
    rescue StandardError
      nil
    end

    expect(breaker.state).to eq(:open)
  end

  it "raises OpenError when circuit is open" do
    3.times do
      breaker.call { raise StandardError }
    rescue StandardError
      nil
    end

    expect { breaker.call { "test" } }.to raise_error(Philiprehberger::RetryKit::CircuitBreaker::OpenError)
  end

  it "transitions to half_open after cooldown" do
    3.times do
      breaker.call { raise StandardError }
    rescue StandardError
      nil
    end

    sleep 0.15
    # Should not raise OpenError — circuit should be half_open
    result = breaker.call { "recovered" }
    expect(result).to eq("recovered")
    expect(breaker.state).to eq(:closed)
  end

  it "resets to closed state" do
    3.times do
      breaker.call { raise StandardError }
    rescue StandardError
      nil
    end

    breaker.reset
    expect(breaker.state).to eq(:closed)
    expect(breaker.failure_count).to eq(0)
  end

  describe "on_state_change" do
    it "calls the callback on state transitions" do
      transitions = []
      cb = described_class.new(
        failure_threshold: 2,
        cooldown: 0.1,
        on_state_change: ->(from, to) { transitions << [from, to] }
      )

      2.times do
        cb.call { raise StandardError }
      rescue StandardError
        nil
      end

      expect(transitions).to include(%i[closed open])
    end

    it "fires on recovery from half_open to closed" do
      transitions = []
      cb = described_class.new(
        failure_threshold: 2,
        cooldown: 0.1,
        on_state_change: ->(from, to) { transitions << [from, to] }
      )

      2.times do
        cb.call { raise StandardError }
      rescue StandardError
        nil
      end

      sleep 0.15
      cb.call { "recovered" }

      expect(transitions).to include(%i[open half_open])
      expect(transitions).to include(%i[half_open closed])
    end
  end
end
