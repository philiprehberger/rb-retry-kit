# frozen_string_literal: true

require_relative "lib/philiprehberger/retry_kit/version"

Gem::Specification.new do |spec|
  spec.name = "philiprehberger-retry_kit"
  spec.version = Philiprehberger::RetryKit::VERSION
  spec.authors = ["Philip Rehberger"]
  spec.email = ["me@philiprehberger.com"]

  spec.summary = "Retry with exponential backoff, jitter, and circuit breaker"
  spec.description = "A lightweight retry library with exponential/linear/constant backoff, " \
                     "configurable jitter strategies, and an optional circuit breaker for " \
                     "resilient Ruby applications."
  spec.homepage = "https://github.com/philiprehberger/rb-retry-kit"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
end
