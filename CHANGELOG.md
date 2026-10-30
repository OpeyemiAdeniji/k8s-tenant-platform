# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- ADR 0004: Kyverno as the admission policy engine, compared with OPA Gatekeeper and the built-in ValidatingAdmissionPolicy.
- Supported platforms section in the README, with the parts that are tied to Linux on x86-64, and an issue for macOS and ARM.
- A third cluster start time in the measurements and in the README.
- `make kyverno-up`, which installs Kyverno with Helm at the chart version that is pinned in `platform/kyverno/chart-version`, and the measured memory cost of the stock install.
- Kyverno policy exceptions, enabled in one namespace (`platform-exceptions`), that expire through a `cleanup.kyverno.io/ttl` label with an absolute date, and the one permission that the cleanup controller needs to delete them.
- ADR 0008: CEL-based Kyverno policies instead of the deprecated `ClusterPolicy`, and exceptions that expire through a TTL label.
- First policy, `disallow-latest-image-tag` (a CEL `ValidatingPolicy` scoped to tenant namespaces), with its offline tests, a message that names the fix and links to a runbook, and the runbook `docs/runbooks/policy-disallow-latest-tag.md`.
- `make policy-test` and the `policy` CI job, which run the offline tests and check that the suite cannot give a false green.
- The Kyverno CLI in `scripts/install-tools.sh` with its checksum, pinned in `platform/kyverno/app-version`, and a check in `make kyverno-up` that the chart installs that version.
- ADR 0009: scope policies to tenant namespaces by label, and test the scope offline with a values file.

### Fixed
- The architecture diagram in the README did not render on GitHub (an error in the label of a dotted arrow). It is removed for now and replaced by a numbered list, until a hand-drawn diagram is added. The v0.1.0 tag still contains the old diagram.

## [0.1.0] - 2026-10-26

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
- Isolation test suite (`make test-isolation`) with 36 checks, in which the test pods are placed on named nodes so that same-node and cross-node traffic are both covered: secrets across tenants, platform controls, network traffic between tenants, noisy neighbour limits and quotas.
- `scripts/install-tools.sh`, which installs pinned versions of kind, kubectl and Helm and checks each download against its checksum.
- `isolation` CI job, which builds the cluster on a GitHub runner and runs the isolation tests.
- Runbook for a failed isolation job, with the first real failure recorded.
- README with the idea, a quick start, the checks and measured results, the known limits and the roadmap.

### Changed
- `make setup` and `CONTRIBUTING.md` now use pre-commit installed with pipx, not a virtualenv.
- The YAML hook skips Helm templates, which are not valid YAML until they are rendered.

[Unreleased]: https://github.com/OpeyemiAdeniji/k8s-tenant-platform/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/OpeyemiAdeniji/k8s-tenant-platform/releases/tag/v0.1.0
