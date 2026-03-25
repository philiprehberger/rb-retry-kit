# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
