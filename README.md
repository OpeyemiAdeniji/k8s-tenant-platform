# k8s-tenant-platform

> A local reference implementation of a self-service, multi-tenant Kubernetes platform. A team asks for a space by adding one file in a pull request, and the platform builds it, with isolation that automated tests prove.

[![CI](https://github.com/OpeyemiAdeniji/k8s-tenant-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/OpeyemiAdeniji/k8s-tenant-platform/actions/workflows/ci.yml)

**Status: v0.1.0.** This is a portfolio project. It is not a production platform, it has no real tenants, and no real team has used it. The section "Known limits" says what is missing.

## The idea

In ticket-based operations, a team that needs a place to run workloads opens a ticket and waits for someone to build a namespace by hand. Hand-built namespaces drift apart, and nobody tests whether they are really isolated.

Here, a team adds one file, `tenants/<name>.yaml`, in a pull request. Continuous integration checks the file against a JSON Schema and renders what it would create. The merge is the approval. The platform then creates a namespace with a resource quota, default limits, access rules and default-deny network policies. The isolation claims are backed by tests that run in continuous integration.

## What this proves

- A tenant contract as a JSON Schema, with tests that show that bad files fail for the right reason, and not just that they fail.
- A Helm chart that turns the contract into the same baseline for every tenant, with a check that every object carries the cost label.
- Isolation tests that perform real actions. Every "must be blocked" check has a matching "must work" check, and a break test shows that the suite fails when the protection is removed.
- A CI job that builds the cluster on a GitHub runner and runs the same suite as a local run.
- A real CI failure, diagnosed from the terminal and written down in a runbook, including what is still unknown.
- Measured numbers only, each with its method and its limits.
- Architecture decision records that explain the choices and the exclusions.

## Architecture

A tenant is created in v0.1 like this:

1. A team adds `tenants/<name>.yaml` in a pull request.
2. Continuous integration checks the file against the JSON Schema and renders the chart for it.
3. The merge to `main` is the approval.
4. `make tenants-apply` renders the file with `helm template` and applies it with `kubectl apply`. This step is manual in v0.1.
5. The cluster now has a namespace `tenant-<name>` with its quota, limits, access rules and network policies.

The tenant file is the only thing that a team edits. In v0.1 the merge is followed by a manual `make tenants-apply`. Argo CD, which would apply and remove tenants automatically, is planned for v0.3 and is not built yet. The cluster is a kind cluster with one control-plane node and two workers, with Calico as the network plugin ([ADR 0003](docs/adr/0003-network-plugin-calico.md)).

## What a tenant file looks like

```yaml
schemaVersion: 1
name: alpha
owner:
  team: alpha
  email: team-alpha@example.com
costCentre: cc-1001
environment: dev
size: small
access:
  admins:
    - alpha-admins
  viewers:
    - alpha-viewers
```

The size selects the quota. These tiers are design choices, not measurements: medium is twice small, and large is four times small.

| Size | requests (CPU, memory) | limits (CPU, memory) | pods | services | volume claims |
|---|---|---|---|---|---|
| small | 500m, 512Mi | 1, 1Gi | 10 | 5 | 2 |
| medium | 1, 1Gi | 2, 2Gi | 20 | 10 | 4 |
| large | 2, 2Gi | 4, 4Gi | 40 | 20 | 8 |

## What every tenant gets

- A namespace `tenant-<name>` with the labels `tenant`, `team`, `cost-centre` and `environment`, an owner annotation, and the Pod Security `restricted` level.
- A `ResourceQuota` for the size, with zero NodePort and LoadBalancer services, and a `LimitRange` that gives containers default requests and limits.
- A custom `tenant-admin` role for the admin groups. It can run workloads, but it cannot change the quota, the limit range or the network policies, and it cannot grant access ([ADR 0007](docs/adr/0007-custom-tenant-admin-role.md)). Viewer groups get the built-in `view` role, which does not include secrets.
- Three network policies that deny all traffic, allow DNS lookups, and allow traffic inside the namespace. They use only the standard NetworkPolicy API.

## Quick start

You need Docker, and Python 3 for the contract checks. The tools are pinned to the versions that were measured.

```bash
bash scripts/install-tools.sh        # kind v0.33.0, kubectl v1.37.1, Helm v4.3.1 in ~/.local/bin
python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
pipx install pre-commit && make setup   # git hooks, once per clone

make help                # list all targets
make validate            # check the tenant files against the contract
make test-contract       # valid files pass, invalid files fail for the right reason
make chart-test          # lint and render the chart for every tenant
make cluster-up          # build the kind cluster and install Calico
make tenants-apply       # render every tenant file and apply it
make test-isolation      # 36 checks against the running cluster
make cluster-down        # remove the cluster
```

## What is proven, and how

`make test-isolation` runs 36 checks, and the same suite runs in CI.

| Property | Checks |
|---|---|
| A tenant cannot read another tenant's secrets, and viewers cannot read secrets | 6 |
| A tenant cannot delete its default-deny policy, quota or limit range, cannot create role bindings, and cannot loosen the Pod Security level | 5 |
| Traffic between pods of one tenant works, on the same node and across nodes. DNS works. Traffic between tenants is blocked, on the same node and across nodes | 14 |
| A CPU hog is held at its limit, a memory hog is killed at its limit, and a quiet tenant on the same node keeps answering | 5 |
| A second pod above the quota, NodePort and LoadBalancer services, and a container above the tier maximum are rejected. A pod without resources gets the default limit | 6 |

The network checks include a check that every test pod runs on the node that the test intended. A break test deleted all six network policies. Exactly the eight checks that must be blocked failed, and the other 28 did not.

## Measured results

One machine (Windows 11 with WSL2, 7.7 GiB of memory, 8 CPUs), single samples. The setup and the method of each number are in [docs/measurements.md](docs/measurements.md).

| What | Result |
|---|---|
| Cluster start, `make cluster-up` | 211 s with images still to download, and 173 s with images cached. `kind create cluster` took 40 s and 35 s of that |
| Memory cost of the cluster | about 1.8 GiB, as the difference in `free -h` before and after (896 MiB used before). The precision is about 0.1 GiB |
| `isolation` CI job on a GitHub runner | between 2m6s and 2m53s in five pull request runs |

## Known limits

- It is a local reference implementation. It has no high availability, no real tenants and no on-call process.
- The kind nodes are containers on one machine and share its CPU and memory. The noisy neighbour checks show that pod limits are enforced, not how a full node behaves.
- The network checks show that traffic between two tenants is blocked. They do not show whether the ingress rules or the egress rules did it, because the policies deny both directions at once. Traffic through a Service or through the host network is not covered.
- The Pod Security level is set on every namespace, but no check yet tries to run a privileged pod. The baseline denies egress to the internet, and no check covers that either.
- Removing a tenant file does not remove the tenant until Argo CD arrives in v0.3. For now, a tenant is removed by deleting its namespace.
- Not built yet: the pull request preview comment, admission policies with friendly messages, time-limited exceptions, the Trivy gate, cost estimates and the platform SLO.
- The size tiers have not been compared with real workloads.
- Calico is installed with its stock custom resources, which include the Goldmane and Whisker flow components. Their memory use has not been separated from the rest.
- Everything was tested with kind v0.33.0, Kubernetes v1.37.0 and Calico v3.33.0 only. Whether Argo CD can use the tenant file as a values file is untested.
- The sample tenants use `example.com` addresses and are not real teams.
- The CI job failed twice before it passed, because a check asked for an exact label that the runner reports differently. [The runbook](docs/runbooks/isolation-job-failed.md) has the evidence and says what is still unknown.

## Design decisions

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-namespace-per-tenant.md) | One namespace per tenant on a shared cluster |
| [0002](docs/adr/0002-pull-request-not-web-portal.md) | A pull request as the interface, and no web portal |
| [0003](docs/adr/0003-network-plugin-calico.md) | Calico as the network plugin, with a measured test of the default plugin |
| [0005](docs/adr/0005-tenant-contract-yaml-json-schema.md) | The tenant contract as plain YAML with a JSON Schema |
| [0006](docs/adr/0006-helm-chart-renders-tenant-file.md) | A Helm chart renders the tenant file |
| [0007](docs/adr/0007-custom-tenant-admin-role.md) | A custom role for tenant admins |

ADR 0004 (the admission policy engine) is reserved for v0.2, so the numbering has a gap on purpose.

## Roadmap

| Version | Scope |
|---|---|
| v0.1 | Tenant contract, namespace, quota, access, network policies, isolation tests. Released. |
| v0.2 | Kyverno guardrails with tests, friendly rejection messages, expiring exceptions, Trivy gate |
| v0.3 | Argo CD ApplicationSet, pull request preview, capacity and cost report, dashboard, platform SLO, runbook, blog post |
| v0.4 | Move to Amazon EKS |

## Repository layout

```
tenants/            one file per tenant, the only place a team edits
schemas/            the JSON Schema of the tenant contract
platform/kind/      the kind cluster configuration
platform/charts/    the Helm chart that renders a tenant
scripts/            cluster, chart, install and validation scripts
tests/contract/     files that must pass and files that must fail the contract
tests/isolation/    the isolation suite
docs/adr/           architecture decision records
docs/runbooks/      runbooks, including a real failure
docs/measurements.md  setup, methods and numbers
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
