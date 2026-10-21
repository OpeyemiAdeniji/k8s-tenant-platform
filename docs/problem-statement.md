# Problem statement

## Summary

k8s-tenant-platform is a local reference implementation of a self-service, multi-tenant Kubernetes platform. A team requests its own space on a shared cluster by adding one tenant file in a pull request. After review and merge, the platform creates a namespace with resource quotas, role-based access control, default-deny network policies, admission policies and a continuous integration template, without a ticket and without manual work by the platform team.

It runs first on kind on a single development machine and is planned to move to Amazon EKS in v0.4. It is a portfolio project that demonstrates platform engineering patterns. It is not a production platform, and it has not been used by real tenant teams.

## The problem

In ticket-based operations, a team that needs somewhere to run workloads opens a ticket and waits. A platform engineer then creates the namespace, quota, access and network rules by hand or with one-off scripts. This causes four recurring problems:

1. **Waiting.** Onboarding speed depends on the platform team's queue, not on the team that asked.
2. **Drift.** Hand-built namespaces differ from each other. Some miss a quota, a network policy or a label, and nobody notices until something goes wrong.
3. **Unproven isolation.** Teams are told they are isolated from each other, but nobody tests it, so the claim rests on trust.
4. **Unclear rejections and invisible cost.** When a workload breaks a rule, the error comes from the API server and does not tell the developer how to fix it. Nobody can say what each team's share of the cluster costs.

The platform team becomes a bottleneck, and much of its work is repetitive toil.

## What this platform does instead

1. A team opens a pull request that adds one file, `tenants/<name>.yaml`.
2. Continuous integration validates the file against a JSON Schema (the tenant contract) and posts a preview comment that lists exactly what will be created.
3. A platform engineer reviews and merges. The review replaces the ticket as the approval step.
4. Argo CD detects the new file and creates the tenant through an ApplicationSet. Deleting the file offboards the tenant.
5. Kyverno admission policies reject unsafe workloads with messages written for developers: what is wrong, how to fix it, and a runbook link.
6. Automated tests prove isolation between tenants on every change.

## Users

- **Tenant teams:** application developers who need a namespace, sensible limits and a working continuous integration template, and who should not need to learn platform internals.
- **Platform team:** the engineers who own the cluster, the contract and the policies, and who want guardrails and evidence instead of manual checks.

## Goals

1. **Tenant contract:** a JSON Schema for the tenant file, validated in continuous integration.
2. **Pull request preview:** a comment that shows the resources a tenant file will create.
3. **Proven isolation,** by automated tests that run in continuous integration:
   - no network traffic between tenants, using a network plugin that enforces NetworkPolicy (the choice is recorded in ADR 0003);
   - no access to another tenant's secrets;
   - resource quotas are enforced;
   - a noisy neighbour cannot take resources beyond its own quota and limits.
4. **Policy as code:** Kyverno policies, each with passing and failing cases run by `kyverno test` in continuous integration.
5. **Developer-friendly rejections:** every policy message states the problem, the fix and a runbook link.
6. **Time-limited exceptions:** every policy exception carries an expiry date and stops applying automatically when the date passes.
7. **GitOps lifecycle:** an Argo CD ApplicationSet creates one tenant per file, and removing the file offboards the tenant.
8. **Cost showback:** cost labels on every tenant and a monthly cost estimate per tenant, calculated from its quota.
9. **Platform SLO:** time from a merged pull request to a ready tenant, with a measured result.
10. **Supply chain gate:** a Trivy scan in the tenant continuous integration template that fails the build on serious findings.

## Non-goals

These are deliberate exclusions. Each one is explained in an ADR.

- **Web portal or Backstage.** The pull request is the self-service interface (ADR 0002).
- **Multi-cluster and cluster per tenant.** One shared cluster with a namespace per tenant (ADR 0001).
- **Service mesh.** Network isolation uses NetworkPolicy enforced by the network plugin (ADR 0003).
- **Production operation.** No high availability, no real tenants and no on-call rota. The hardening that production would need is listed in the runbook and the ADRs instead of being claimed.

## Constraints

- Runs on one development machine: Windows 11, WSL2 Ubuntu, Docker Desktop and kind. Every component must fit in the memory available to Docker.
- Uses free and open source tools only until the move to EKS in v0.4.
- One maintainer, so automation and tests replace manual review wherever possible.
- Every number published in this repository is measured on the setup described here, with the method recorded. No estimated or borrowed number is presented as a result.

## Definition of done

1. One command builds the cluster and installs the platform.
2. A sample pull request onboards a tenant.
3. A bad workload is rejected with a helpful message.
4. The isolation tests pass in continuous integration.
5. One command tears everything down.

## How success is measured

**Service level indicator:** the time from the merge commit of a tenant pull request reaching `main` to the tenant being ready. Ready means that the namespace and all baseline resources exist and Argo CD reports the tenant as synced and healthy. The exact definition and the measurement script will be added in v0.3.

**Service level objective:** the target will be set after a baseline has been measured, not before. By default Argo CD checks Git on a polling interval, and a GitHub webhook cannot reach a development machine without a tunnel, so the local measurement will include polling time. The result will be reported with that caveat.

**Cost estimate:** calculated as quota multiplied by a documented unit price. It is an estimate for showback, not a bill, and the source of every unit price will be recorded.

## Release plan

| Version | Scope |
|---|---|
| v0.1 | Tenant contract and schema, namespace, quota, RBAC, network policy, isolation tests |
| v0.2 | Kyverno guardrails with tests, developer-friendly errors, expiring exceptions, Trivy gate |
| v0.3 | Argo CD ApplicationSet, pull request preview, capacity and cost report, dashboard, platform SLO, runbook, blog post |
| v0.4 | Move to Amazon EKS |
