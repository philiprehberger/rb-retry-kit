# philiprehberger-retry_kit

[![Tests](https://github.com/philiprehberger/rb-retry-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-retry-kit/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-retry_kit.svg)](https://rubygems.org/gems/philiprehberger-retry_kit)
[![Last updated](https://img.shields.io/github/last-commit/philiprehberger/rb-retry-kit)](https://github.com/philiprehberger/rb-retry-kit/commits/main)

![philiprehberger-retry_kit](https://raw.githubusercontent.com/philiprehberger/rb-retry-kit/main/package-card.webp)

Retry with exponential backoff, jitter, and circuit breaker

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-retry_kit"
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

Options are validated up front. `Executor.new` / `RetryKit.run` raise `ArgumentError` immediately for an unknown `backoff:` strategy or `jitter:` mode, `max_attempts` below 1, a negative `base_delay`, or a `max_delay` smaller than `base_delay` — so a misconfiguration surfaces at construction time instead of silently succeeding.

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

Backoff sleeps are clamped to the remaining budget: if a computed delay would sleep past `total_timeout` (or `deadline`), it is shortened to the time left, and `TotalTimeoutError` / `DeadlineExceededError` is raised as soon as no budget remains — the executor never overshoots the stated bound by sleeping a full backoff delay.

### Absolute Deadline

Stop retrying once a specific wall-clock `Time` has passed. Useful when the caller has a hard SLA (e.g. "respond before the request times out") rather than a relative budget:

```ruby
Philiprehberger::RetryKit.run(
  max_attempts: 50,
  deadline: Time.now + 10  # raises DeadlineExceededError once Time.now >= deadline
) do
  api_call
end
```

`deadline:` composes with `total_timeout:` — whichever is hit first wins. `DeadlineExceededError` is never caught by the `on:` retryable-errors filter, so it always propagates.

### Execution Stats

Use `Executor` directly to access stats after execution:

```ruby
executor = Philiprehberger::RetryKit::Executor.new(max_attempts: 5)
executor.call { api.request }

executor.last_attempts     # => 3 (number of attempts made)
executor.last_total_delay  # => 3.5 (total seconds spent in backoff sleeps)
```

### Decorrelated Jitter

AWS-style decorrelated jitter provides better delay distribution than full or equal jitter:

```ruby
Philiprehberger::RetryKit.run(
  backoff: :exponential,
  jitter: :decorrelated,
  base_delay: 0.5,
  max_delay: 30
) do
  api_call
end
```

Each delay is randomized between `base_delay` and `3 * last_sleep`, capped at `max_delay`.

### Fallback Handler

Execute alternative code when all retries are exhausted instead of raising:

```ruby
result = Philiprehberger::RetryKit.run(
  max_attempts: 3,
  fallback: ->(error) { default_value }
) do
  unreliable_call
end
```

The fallback proc receives the last error and its return value becomes the result of `run`.

### Retry Predicate

Custom predicate for fine-grained retry decisions beyond exception class filtering:

```ruby
Philiprehberger::RetryKit.run(
  retry_if: ->(error, attempt) { error.message.include?("timeout") && attempt < 3 }
) do
  api_call
end
```

If `retry_if` returns false, retrying stops immediately even if `max_attempts` has not been reached. Works in addition to the `on:` exception class filter (both must pass).

### Per-Attempt Callback

Hook called after every attempt (not just retries) for metrics and logging:

```ruby
Philiprehberger::RetryKit.run(
  on_attempt: ->(attempt, duration, error) {
    puts "Attempt #{attempt} took #{duration}s#{error ? " (failed: #{error.message})" : ""}"
  }
) do
  api_call
end
```

Called after each attempt with: attempt number (1-based), duration in seconds, and error (`nil` on success).

### Give-up Callback

Fired exactly once when the executor stops retrying (attempts exhausted, `retry_if` returned false, or budget ran out). Runs before the `fallback` is invoked or the error is re-raised:

```ruby
Philiprehberger::RetryKit.run(
  max_attempts: 3,
  on_giveup: ->(error, attempts) {
    Metrics.increment("retry.giveup", tags: { reason: error.class.name, attempts: attempts })
  }
) do
  unreliable_call
end
```

Useful for metrics, alerting, and structured logging at the point of failure.

### Success Callback

Fired exactly once after the executor produces a successful result — whether on the first attempt or after retries. Receives `(attempts, total_delay, return_value)`:

```ruby
Philiprehberger::RetryKit.run(
  on_success: ->(attempts, total_delay, value) {
    Metrics.histogram("retry.attempts", attempts)
    Metrics.histogram("retry.total_delay", total_delay) if attempts > 1
  }
) do
  api_call
end
```

Differs from `on_attempt`, which fires after *every* attempt (including failed ones). `on_success` is the right place for aggregate success metrics.

### Retry Budget

Global retry budget shared across executors to prevent retry storms:

```ruby
budget = Philiprehberger::RetryKit::Budget.new(max_retries: 100, window: 60)

# Multiple executors share the budget
Philiprehberger::RetryKit.run(budget: budget) { call_a }
Philiprehberger::RetryKit.run(budget: budget) { call_b }

budget.remaining   # => remaining retry count
budget.exhausted?  # => true/false
budget.reset       # clear all recorded retries
```

Thread-safe sliding window counter. When the budget is exhausted, retries are skipped and the error is raised immediately (or the fallback is invoked if provided).

### Presets

Named retry presets cover common scenarios so you don't have to tune knobs from scratch. Pass any keyword to override the preset's defaults:

```ruby
# Tuned for transient HTTP errors
Philiprehberger::RetryKit.with_preset(:network) do
  http_request
end

# Override individual options as needed
Philiprehberger::RetryKit.with_preset(:network, max_attempts: 6, on: [Net::ReadTimeout]) do
  http_request
end
```

Available presets:

- `:aggressive` — small `max_attempts`, short delays, full jitter, exponential backoff. For low-latency calls where giving up fast is preferable to waiting.
- `:conservative` — larger `max_attempts`, longer delays, full jitter, exponential. For background work where success matters more than speed.
- `:network` — middle ground tuned for transient HTTP errors.
- `:database` — short to medium delays with equal jitter for transient DB errors (deadlocks, serialization failures, connection drops); these typically self-heal quickly or escalate fast.
- `:fast` — minimal-latency preset (3 attempts, 20 ms base, 200 ms cap, full jitter) for in-process caches, fast RPC, and interactive paths where waiting hurts more than failing.

Inspect the table directly via `Philiprehberger::RetryKit::PRESETS`. The constant and each preset hash are frozen.

### Listing Presets

```ruby
Philiprehberger::RetryKit.preset_names
# => [:aggressive, :conservative, :network, :database, :fast]
```

Useful for surfacing the available presets in CLI tooling, dashboards, or
validating user-supplied preset names without poking at `PRESETS`.

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
breaker.reset        # reset to closed
breaker.trip!        # force open immediately (operational kill-switch)
```

After the cooldown elapses the circuit becomes half-open and probes with a **single trial**: only the first caller is allowed through, and concurrent callers receive `OpenError` until the probe resolves. A successful probe closes the circuit; a failed probe re-opens it and starts a fresh cooldown. This prevents a thundering herd from hammering a dependency that is still recovering.

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
| `RetryKit.with_preset(name, **overrides, &block)` | Execute a block using a named preset, with optional overrides |
| `RetryKit::PRESETS` | Frozen Hash of named preset option Hashes (`:aggressive`, `:conservative`, `:network`, `:database`, `:fast`) |
| `RetryKit.preset_names` | Array of preset names registered in `PRESETS` |
| `Executor.new(**options)` | Create a reusable retry executor |
| `Executor#call(&block)` | Execute the block with retries |
| `Executor#last_attempts` | Number of attempts in the last execution |
| `Executor#last_total_delay` | Total backoff sleep time (seconds) in the last execution |
| `CircuitBreaker.new(failure_threshold:, cooldown:)` | Create a circuit breaker |
| `CircuitBreaker#call(&block)` | Execute through the circuit breaker |
| `CircuitBreaker#state` | Current state (`:closed`, `:open`, `:half_open`) |
| `CircuitBreaker#reset` | Reset to closed state |
| `CircuitBreaker#trip!` | Force the circuit open (operational kill-switch) |
| `Backoff.exponential(attempt, base_delay:, max_delay:)` | Calculate exponential delay |
| `Backoff.linear(attempt, base_delay:, max_delay:)` | Calculate linear delay |
| `Backoff.constant(attempt, delay:)` | Calculate constant delay |
| `Backoff.jitter(delay, mode:)` | Apply jitter to a delay (`:full`, `:equal`, `:none`) |
| `Backoff.decorrelated(last_delay, base_delay:, max_delay:)` | Calculate decorrelated jitter delay |
| `Budget.new(max_retries:, window:)` | Create a shared retry budget |
| `Budget#acquire` | Consume one retry from the budget |
| `Budget#remaining` | Remaining retries in the current window |
| `Budget#exhausted?` | Whether the budget is exhausted |
| `Budget#reset` | Clear all recorded retries |
| `TotalTimeoutError` | Raised when `total_timeout` is exceeded |
| `DeadlineExceededError` | Raised when the absolute `deadline:` has passed |

### Callbacks

The options below are **callback options** passed to `RetryKit.run` / `Executor.new`, not methods. Each accepts a callable (proc or lambda) and is invoked at the documented lifecycle point.

| Callback option | Signature | When it fires |
|-----------------|-----------|---------------|
| `on_retry:` | `->(error, attempt, delay) { ... }` | Before each retry sleep, after a failed attempt that will be retried |
| `on_attempt:` | `->(attempt, duration, error) { ... }` | After every attempt (success or failure), useful for per-attempt metrics |
| `on_success:` | `->(attempts, total_delay, value) { ... }` | Exactly once on eventual success, with aggregate stats and the return value |
| `on_giveup:` | `->(error, attempts) { ... }` | Exactly once when the executor stops retrying, before fallback or re-raise |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Support

If you find this project useful:

⭐ [Star the repo](https://github.com/philiprehberger/rb-retry-kit)

🐛 [Report issues](https://github.com/philiprehberger/rb-retry-kit/issues?q=is%3Aissue+is%3Aopen+label%3Abug)

💡 [Suggest features](https://github.com/philiprehberger/rb-retry-kit/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)

❤️ [Sponsor development](https://github.com/sponsors/philiprehberger)

🌐 [All Open Source Projects](https://philiprehberger.com/open-source-packages)

💻 [GitHub Profile](https://github.com/philiprehberger)

🔗 [LinkedIn Profile](https://www.linkedin.com/in/philiprehberger)

## License

[MIT](LICENSE)
