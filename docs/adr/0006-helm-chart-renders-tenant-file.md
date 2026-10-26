# 0006. A Helm chart turns a tenant file into Kubernetes objects

- Status: accepted
- Date: 2026-10-26

## Context

The tenant file (ADR 0005) describes what a team asks for. Something has to turn it into the objects that every tenant receives: a namespace, a quota, a limit range, access rules and network policies (ADR 0001).

The same rendering is needed in three places: on the local cluster, in continuous integration (to check every tenant file and, from v0.3, to show a preview in the pull request), and in Argo CD from v0.3, where an ApplicationSet creates one tenant per file. Rendering must work without a cluster, so that a pull request can be checked before it is merged. It must also keep the objects of all tenants identical except for the values that the file supplies, because namespaces that were built by hand and drifted apart are the problem this platform exists to remove.

## Options considered

1. **Helm chart that takes the tenant file as its values**: the file is passed with `-f`, so its fields are the chart values.
   - Pros: `helm template` renders without a cluster. The file is used as it is, with no copy per tenant. Labels, size tiers and defaults live in one place. Argo CD can deploy Helm charts and can read YAML files with its files generator, so the same chart should work in v0.3. That has not been tried yet.
   - Cons: the template language is awkward to read and easy to get wrong. The template files are not valid YAML until they are rendered, so the YAML hook has to skip them. Helm does not remove objects that an earlier render created, so a manual `helm template | kubectl apply` does not prune. Argo CD does that from v0.3.
2. **Kustomize**: a base plus one overlay per tenant.
   - Pros: no template language, and it is built into kubectl.
   - Cons: every tenant would need an overlay folder next to its file, so a team would edit more than one file and the contract file would no longer be the single source. Names, labels and quota values would have to be patched in, which is harder to read than a template.
3. **A script that writes the manifests (for example in Python)**: full control and ordinary unit tests.
   - Pros: clear error messages and easy to test.
   - Cons: Argo CD cannot run it without a plugin, so the GitOps step in v0.3 would need a second render path, and the two paths could diverge.

A controller that creates the objects was already rejected in ADR 0005.

## Decision

Use a Helm chart (Option 1). The chart is `platform/charts/tenant`, and the tenant file is passed with `-f`.

- Every tenant receives: a namespace `tenant-<name>` with the labels `tenant`, `team`, `cost-centre` and `environment`, the Pod Security Admission `restricted` level and an owner annotation; a ResourceQuota; a LimitRange; access rules (ADR 0007); and three NetworkPolicy objects that deny all traffic, allow DNS to CoreDNS and allow traffic inside the namespace.
- The labels come from one helper, and `make chart-test` checks that every rendered object carries the cost label.
- The size tiers are defined in `values.yaml`. They are design choices, not measurements. Medium is twice small, and large is four times small. Every tier sets node port and load balancer services to zero.
- An unknown size makes the chart fail with a clear message. This is a second layer after the contract check.
- The baseline does not allow egress to the internet. A tenant that needs it will use a time-limited exception in v0.2.
- The continuous integration job `chart` runs `make chart-test` with Helm pinned to v4.3.1.

## Consequences

- Verified on 2026-10-26 with Helm v4.3.1 and Kubernetes v1.37.0: both sample tenants lint, render and apply on the local cluster, and the quota, limit range, role bindings and network policies exist as designed.
- Not verified: that Argo CD can use the tenant file as a values file. This is planned for v0.3, with `valuesObject` as the fallback. Argo CD bundles its own Helm version, so that version has to be compared with v4.3.1 then.
- Removing a tenant file does not remove the tenant until Argo CD with pruning arrives in v0.3. Until then a tenant is removed by deleting its namespace.
- The size tiers are not backed by measurements of real workloads. The capacity report in v0.3 has to say so.
- Revisit this decision if Argo CD cannot consume the tenant file, or if the templates become hard to maintain.
