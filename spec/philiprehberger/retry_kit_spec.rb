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
