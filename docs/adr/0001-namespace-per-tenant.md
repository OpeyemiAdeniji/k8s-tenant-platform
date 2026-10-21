# 0001. Namespace per tenant on a shared cluster

- Status: accepted
- Date: 2026-10-21

## Context

The platform must give each team (a tenant) its own space with limits, access control and network isolation, created from one file in a pull request. Something has to be the unit of isolation between tenants.

The tenants in this design are internal teams of one organisation. They are trusted not to attack each other on purpose, but they must not be able to affect each other by accident: by reading each other's secrets, by sending traffic to each other's workloads, or by using up shared capacity. The Kubernetes documentation calls this the multi-team case, as opposed to the multi-customer case, where tenants do not trust each other.

The platform runs first on kind on a single development machine with limited memory, and later moves to Amazon EKS, where every cluster has its own control plane charge. Onboarding must be quick and simple enough to measure as a platform SLO, and offboarding must happen by deleting the tenant file.

## Options considered

1. **Namespace per tenant on a shared cluster**: each tenant gets one namespace on one cluster, with ResourceQuota, LimitRange, Role and RoleBinding, default-deny NetworkPolicy and admission policies.
   - Pros: onboarding creates a small number of Kubernetes objects and needs no infrastructure. It uses controls that are built into Kubernetes and well documented. One cluster means one Argo CD, one policy engine and one network plugin to operate and test. It fits the memory of a single development machine.
   - Cons: tenants share the control plane, the nodes and the node kernels. Cluster-scoped resources such as custom resource definitions, cluster roles and admission webhooks are shared as well. Isolation is only as strong as the combination of controls, so one missing control silently weakens it, and this must be tested, not assumed. One tenant can still put load on the shared API server, which namespace quotas only partly limit.
2. **Cluster per tenant**: each tenant gets its own cluster.
   - Pros: the strongest isolation, with separate control planes, nodes and cluster-scoped resources. Each tenant can be upgraded and configured independently.
   - Cons: every cluster repeats the control plane and the platform add-ons: policy engine, network plugin, monitoring and a connection to Argo CD. On one development machine, several kind clusters compete for the same memory. On EKS, every cluster adds a control plane charge. Onboarding becomes cluster provisioning, which is slower and harder to measure as a simple SLO. It needs fleet management across clusters, which this project excludes.
3. **Virtual cluster per tenant (for example vCluster)**: each tenant gets a virtual control plane that runs inside a namespace of a shared host cluster.
   - Pros: tenants can install their own custom resource definitions and cluster-scoped resources without affecting each other. It is cheaper than real clusters, because workloads still run on shared nodes.
   - Cons: it adds another component to install, upgrade and debug, plus a synchronisation layer between the virtual and host clusters. The host namespace still needs quotas, network policies and admission policies, so this option adds to Option 1 and does not replace it. The tenants described here need a namespace, not their own control plane.

## Decision

Use one namespace per tenant on a shared cluster (Option 1). It is the only option that fits one development machine, keeps onboarding to a small and measurable Git change, and still moves to EKS without structural change.

- Each tenant file creates exactly one namespace in v0.1. Several namespaces per tenant, for example one per environment, can be added later through the tenant contract.
- Every tenant namespace receives the same baseline: labels for ownership and cost, ResourceQuota, LimitRange, a Role and RoleBinding for the team, default-deny NetworkPolicy with an allowance for DNS, and the Pod Security Admission `restricted` level.
- Tenants receive no cluster-scoped permissions.
- Each isolation property is claimed only when an automated test proves it, and those tests run in continuous integration.

Cluster per tenant and multi-cluster operation are out of scope for this project.

## Consequences

- Onboarding and offboarding are small, reviewable Git changes.
- The whole platform fits on one development machine, and the same design moves to EKS without structural change.
- Tenants share the control plane, nodes and kernels, so this model is not suitable for tenants that do not trust each other.
- Tenants cannot install their own custom resource definitions or other cluster-scoped resources.
- The platform team is responsible for keeping every layer of control in place, which is why the isolation tests are part of v0.1.
- ADR 0003 chooses the network plugin that enforces the network policies, and ADR 0004 chooses the admission policy engine.
- Revisit this decision if tenants become untrusted (for example external customers), need their own cluster-scoped resources, need separate control planes for compliance, or if the shared API server becomes a measured bottleneck.
