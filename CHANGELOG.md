# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.1] - 2026-06-14

### Changed
- Documentation polish in README API section

## [0.8.0] - 2026-05-20

### Added
- `on_success:` callback — fired exactly once with `(attempts, total_delay, return_value)` when an execution eventually succeeds, complementing `on_attempt` (per-attempt) and `on_giveup` (terminal failure). Intended for aggregate success metrics.
- Card image reference in the README for registry-side rendering

## [0.7.0] - 2026-05-13

### Added
- `:fast` preset in `PRESETS` — minimal-latency settings (3 attempts, 20 ms base, 200 ms cap, full jitter) for in-process caches, fast RPC, and interactive paths.

## [0.6.0] - 2026-04-27

### Added
- `:database` preset in `PRESETS` — short delays with equal jitter for transient DB errors (deadlocks, serialization failures, connection drops).
- `RetryKit.preset_names` — returns the list of registered preset names without exposing the underlying constant.

## [0.5.0] - 2026-04-26

### Added
- `PRESETS` — frozen Hash of named retry presets (`:aggressive`, `:conservative`, `:network`); each preset hash is also frozen
- `RetryKit.with_preset(name, **overrides, &block)` — apply a named preset (with optional per-call overrides) and execute the block; raises `ArgumentError` for unknown preset names

## [0.4.0] - 2026-04-15

### Added
- `deadline:` option — absolute wall-clock `Time` cutoff; raises `DeadlineExceededError` once reached (complements the relative `total_timeout:`)
- `on_giveup:` callback — fires exactly once when the executor stops retrying, before the fallback runs or the error is re-raised; ideal for metrics and alerting
- `Budget#reset` — clear all recorded retries from a shared budget
- `CircuitBreaker#trip!` — operational kill-switch that forces the circuit open without waiting for the failure threshold

## [0.3.7] - 2026-03-31

### Added
- Add GitHub issue templates, dependabot config, and PR template

## [0.3.6] - 2026-03-31

### Changed
- Standardize README badges, support section, and license format

## [0.3.5] - 2026-03-26

### Changed

- Add Sponsor badge and fix License link format in README

## [0.3.4] - 2026-03-24

### Changed
- Expand test coverage to 65+ examples covering edge cases and error paths

## [0.3.3] - 2026-03-24

### Fixed
- Fix README one-liner to remove trailing period and match gemspec summary

## [0.3.2] - 2026-03-24

### Fixed
- Remove inline comments from Development section to match template

## [0.3.1] - 2026-03-22

### Changed
- Update rubocop configuration for Windows compatibility

## [0.3.1] - 2026-03-21

### Fixed
- Standardize Installation section in README

## [0.3.0] - 2026-03-16

### Added
- Decorrelated jitter mode (`jitter: :decorrelated`) — AWS-style algorithm with better delay distribution
- Fallback handler (`fallback:`) — execute alternative code when all retries are exhausted instead of raising
- Retry predicate (`retry_if:`) — custom predicate for fine-grained retry decisions beyond exception class filtering
- Per-attempt callback (`on_attempt:`) — hook called after every attempt for metrics/logging
- Retry budget (`Budget`) — thread-safe sliding window counter shared across executors to prevent retry storms

## [0.2.2] - 2026-03-12

### Fixed
- Add License badge to README
- Add bug_tracker_uri to gemspec

## [0.2.1] - 2026-03-12

### Fixed
- Re-release with no code changes (RubyGems publish fix)

## [0.2.0] - 2026-03-12

### Added
- `total_timeout` option to raise `TotalTimeoutError` when total elapsed time exceeds limit
- Execution stats: `last_attempts` and `last_total_delay` on Executor
- `on_state_change` callback on CircuitBreaker for state transition notifications

### Fixed
- Removed undocumented `:decorrelated` jitter mode from docstring (was never implemented)

## [0.1.0] - 2026-03-10

### Added
- Initial release
- Exponential, linear, and constant backoff strategies
- Full and equal jitter modes
- Circuit breaker with configurable threshold and cooldown
- Retry executor with max attempts, retryable error filtering, and on_retry callback
- Convenience `RetryKit.run` class method

[Unreleased]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.8.1...HEAD
[0.8.1]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.3.7...v0.4.0
[0.3.7]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/philiprehberger/rb-retry-kit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/philiprehberger/rb-retry-kit/releases/tag/v0.1.0
