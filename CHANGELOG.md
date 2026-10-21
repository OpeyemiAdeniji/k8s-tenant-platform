# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project structure from the repo template.
- Problem statement with goals, non-goals, constraints, definition of done and how success is measured.
- ADR 0001: namespace per tenant on a shared cluster.
- Tenant contract: JSON Schema, validation script and sample tenants `alpha` and `bravo`.
- Contract tests with valid and invalid examples, where each invalid file declares the message it must produce.
- `contract` CI job, plus `make validate` and `make test-contract`.
- ADR 0005: tenant contract as plain YAML with a JSON Schema.

### Changed
- `make setup` and `CONTRIBUTING.md` now use pre-commit installed with pipx, not a virtualenv.
