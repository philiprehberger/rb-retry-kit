# philiprehberger-retry_kit

[![Tests](https://github.com/philiprehberger/rb-retry-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-retry-kit/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-retry_kit.svg)](https://rubygems.org/gems/philiprehberger-retry_kit)

Retry with exponential backoff, jitter, and circuit breaker for resilient Ruby applications.

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-retry_kit"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install philiprehberger-retry_kit
```

## Usage

```ruby
require "philiprehberger/retry_kit"

# Simple retry with defaults (3 attempts, exponential backoff, full jitter)
result = Philiprehberger::RetryKit.run do
  api.call
end
```

### Custom Options

```ruby
Philiprehberger::RetryKit.run(
  max_attempts: 5,
  backoff: :exponential,
  base_delay: 1,
  max_delay: 60,
  jitter: :equal,
  on: [Net::ReadTimeout, Errno::ECONNRESET]
) do
  http_request
end
```

### Retry Callback

```ruby
Philiprehberger::RetryKit.run(
  max_attempts: 4,
  on_retry: ->(error, attempt, delay) {
    puts "Attempt #{attempt} failed: #{error.message}. Retrying in #{delay}s..."
  }
) do
  flaky_operation
end
```

### Total Timeout

Limit the total elapsed time across all retries:

```ruby
Philiprehberger::RetryKit.run(
  max_attempts: 10,
  total_timeout: 30  # seconds — raises TotalTimeoutError if exceeded
) do
  slow_operation
end
```

### Execution Stats

Use `Executor` directly to access stats after execution:

```ruby
executor = Philiprehberger::RetryKit::Executor.new(max_attempts: 5)
executor.call { api.request }

executor.last_attempts     # => 3 (number of attempts made)
executor.last_total_delay  # => 3.5 (total seconds spent in backoff sleeps)
```

### Backoff Strategies

```ruby
# Exponential: 0.5s, 1s, 2s, 4s, ...
Philiprehberger::RetryKit.run(backoff: :exponential)

# Linear: 0.5s, 1s, 1.5s, 2s, ...
Philiprehberger::RetryKit.run(backoff: :linear)

# Constant: 1s, 1s, 1s, ...
Philiprehberger::RetryKit.run(backoff: :constant, base_delay: 1)
```

### Circuit Breaker

```ruby
breaker = Philiprehberger::RetryKit::CircuitBreaker.new(
  failure_threshold: 5,
  cooldown: 30,
  on_state_change: ->(from, to) { puts "Circuit: #{from} -> #{to}" }
)

# Use with retry
Philiprehberger::RetryKit.run(circuit_breaker: breaker) do
  external_service.call
end

# Use standalone
breaker.call { risky_operation }

# Check state
breaker.state        # => :closed, :open, or :half_open
breaker.failure_count
breaker.reset
```

### Backoff Utilities

```ruby
Philiprehberger::RetryKit::Backoff.exponential(3, base_delay: 0.5, max_delay: 30)
# => 4.0

Philiprehberger::RetryKit::Backoff.jitter(4.0, mode: :full)
# => 0.0..4.0 (random)
```

## API

| Method / Class | Description |
|----------------|-------------|
| `RetryKit.run(**options, &block)` | Execute a block with retry logic |
| `Executor.new(**options)` | Create a reusable retry executor |
| `Executor#call(&block)` | Execute the block with retries |
| `CircuitBreaker.new(failure_threshold:, cooldown:)` | Create a circuit breaker |
| `CircuitBreaker#call(&block)` | Execute through the circuit breaker |
| `CircuitBreaker#state` | Current state (`:closed`, `:open`, `:half_open`) |
| `CircuitBreaker#reset` | Reset to closed state |
| `Backoff.exponential(attempt, base_delay:, max_delay:)` | Calculate exponential delay |
| `Backoff.linear(attempt, base_delay:, max_delay:)` | Calculate linear delay |
| `Backoff.constant(attempt, delay:)` | Calculate constant delay |
| `Backoff.jitter(delay, mode:)` | Apply jitter to a delay (`:full`, `:equal`, `:none`) |
| `Executor#last_attempts` | Number of attempts in the last execution |
| `Executor#last_total_delay` | Total backoff sleep time (seconds) in the last execution |
| `TotalTimeoutError` | Raised when `total_timeout` is exceeded |

## Development

```bash
bundle install
bundle exec rspec      # Run tests
bundle exec rubocop    # Check code style
```

## License

MIT
