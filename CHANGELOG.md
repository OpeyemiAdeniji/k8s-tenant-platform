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
- ADR 0002: pull request as the self-service interface, not a web portal.
- ADR 0003: network plugin for NetworkPolicy enforcement, with a measured test of the default kind plugin.
- Local kind cluster with one control-plane node and two workers, with Calico v3.33.0 as the network plugin.
- `make cluster-up` and `make cluster-down`, which build and remove the cluster in one command each.
- Measurements document with the setup and the method behind each number.
- Tenant Helm chart (`platform/charts/tenant`): namespace, quota, limit range, access rules and default-deny network policies for every tenant file.
- `make chart-test` and the `chart` CI job, which lint and render the chart for every tenant and check that every object carries the cost label.
- `make tenants-apply`, which renders every tenant file and applies it to the local cluster.
- ADR 0006: Helm chart as the renderer of the tenant file.
- ADR 0007: custom tenant admin role instead of the built-in roles.
- Isolation test suite (`make test-isolation`) with 27 checks: secrets across tenants, platform controls, network traffic between tenants, noisy neighbour limits and quotas.

### Changed
- `make setup` and `CONTRIBUTING.md` now use pre-commit installed with pipx, not a virtualenv.
- The YAML hook skips Helm templates, which are not valid YAML until they are rendered.
