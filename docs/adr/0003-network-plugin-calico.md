# 0003. Calico as the network plugin, tested against the standard NetworkPolicy API

- Status: accepted
- Date: 2026-10-26

## Context

Network isolation between tenants depends on NetworkPolicy. A NetworkPolicy object has no effect unless the network plugin of the cluster enforces it, so a cluster that accepts the object but ignores it gives a false sense of safety.

The first design assumed that the default plugin of kind does not enforce NetworkPolicy. This was tested on kind v0.33.0 (node image `kindest/node:v1.37.0`, kubectl v1.37.1). The default plugin is kindnet. In one namespace, a client could reach an nginx server before a deny-all ingress policy existed, and the request timed out after the policy was applied. So kindnet enforces ingress policy in this version. The test used one node, one namespace and ingress only. It does not prove cross-node traffic, egress rules or isolation between namespaces.

kindnet is part of kind and does not run on Amazon EKS, where this platform moves in v0.4. Isolation results that depend on a component that production will not use say little about production. The machine has 7.7 GiB of memory shared by everything, so the cost of each component matters. In one `docker stats` sample taken right after the test, the node container of an idle single-node cluster with kindnet used 668.1 MiB.

## Options considered

1. **kindnet, the default plugin of kind**: nothing to install.
   - Pros: no extra components, the fastest cluster start and the lowest memory use. Enforcement of ingress policy was observed on this machine.
   - Cons: it exists only in kind, so the results do not carry over to EKS. It implements the standard NetworkPolicy API only. Egress, multi-node and cross-namespace behaviour have not been tested yet.
2. **Calico**: the cluster is created with the default plugin disabled and Calico is installed afterwards.
   - Pros: widely used and documented for kind. It can also run on EKS, so the same policy engine can be used in both environments. It implements the standard NetworkPolicy API and has its own policy types, which the tenant baseline does not need.
   - Cons: more components to run, which means more memory and a longer cluster start. The memory and start time have not been measured yet. Nodes stay `NotReady` until Calico is installed, so the cluster build has to wait for it.
3. **Cilium**: the cluster is created with the default plugin disabled and Cilium is installed afterwards.
   - Pros: eBPF dataplane, flow visibility with Hubble, and policies beyond layer 4. It can also run on EKS.
   - Cons: the heaviest option, and it depends on kernel features. The kernel of this machine is recent (6.18.54.1-microsoft-standard-WSL2), but Cilium has not been tried here. Its extra features are not needed, and the layer 7 and mesh-like features overlap with the service mesh that this project excludes.

## Decision

Use Calico (Option 2).

- The cluster is created with the default plugin disabled, and Calico is installed before anything else.
- Tenant isolation uses only the standard NetworkPolicy API. Calico-specific policy types are not used for it, so the isolation tests are portable and run on any plugin that enforces NetworkPolicy.
- The same isolation suite can be run on the default kindnet cluster as a comparison. Any difference in memory or behaviour is recorded with its measurement.

## Consequences

- The project does not depend on a kind-only component for its isolation claims.
- The cluster build gets one more step and uses more memory. The cost is measured when Calico is installed and recorded with the method that produced it.
- Calico has not been installed on this machine yet. If it cannot run on WSL2 or uses too much memory, revisit this decision and record the evidence.
- The isolation tests must cover egress, traffic between nodes and traffic between namespaces, because the test above did not.
- At v0.4, check what the network plugin options of EKS offer before assuming that Calico is the best choice there.
- Revisit this decision if the tests show that kindnet is enough for every isolation property and Calico adds cost without benefit.
