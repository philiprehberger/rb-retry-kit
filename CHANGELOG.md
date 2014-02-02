# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-03-10

### Added
- Initial release
- Exponential, linear, and constant backoff strategies
- Full and equal jitter modes
- Circuit breaker with configurable threshold and cooldown
- Retry executor with max attempts, retryable error filtering, and on_retry callback
- Convenience `RetryKit.run` class method
