# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
