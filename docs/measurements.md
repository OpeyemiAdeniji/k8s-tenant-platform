# Measurements

Every number in this repository is measured on the setup below, and each result states how it was taken. These are single samples from one machine and carry no error margin, so treat them as indications and not as benchmarks.

## Setup

| Item | Value |
|---|---|
| Machine | Windows 11, 15.8 GB of memory |
| WSL2 | Ubuntu, 7.7 GiB of memory, 8 CPUs, 2.0 GiB swap, kernel 6.18.54.1-microsoft-standard-WSL2 |
| Docker Desktop | WSL2 backend, server 29.8.2 |
| kind | v0.33.0 |
| Kubernetes (node image) | kindest/node:v1.37.0 |
| kubectl | v1.37.1 |
| Helm | v4.3.1 (Go 1.27.2) |
| Calico | v3.33.0, installed with the Tigera Operator and the stock custom resources |
| Cluster | 1 control-plane node and 2 workers |

## Cluster start time (v0.1)

Method: `make cluster-up` prints the time that `kind create cluster` took, and the total time until all nodes and both CoreDNS pods are ready. It uses the bash `SECONDS` counter.

| Run | kind create | Total until ready | Notes |
|---|---|---|---|
| 1 | 40 s | 211 s | Node image already on disk. Calico images downloaded during the run. |
| 2 | 35 s | 173 s | All images already on disk. |

## Memory cost of the cluster (v0.1)

Method: `free -h` on WSL before the cluster existed, and about two minutes after `make cluster-up` finished. The cost is the difference in the `used` column. `free -h` rounds to 0.1 GiB, so the difference of about 1.8 GiB has an uncertainty of roughly 0.1 GiB.

| Reading | used | available |
|---|---|---|
| Baseline, no containers running | 896 MiB | 6.8 GiB |
| Cluster running, run 1 | 2.7 GiB | 5.0 GiB |
| Cluster running, run 2 | 2.7 GiB | 5.0 GiB |

`docker stats --no-stream` reports about 3.8 to 4.1 GiB for the three node containers added together. This is higher than the `free` difference. The `buff/cache` column of `free` rose from 1.9 GiB to 5.2 GiB over the same period, which is consistent with `docker stats` counting file cache. That was not separated, so the `free` difference is used as the cost of the cluster.

## Calico enforces NetworkPolicy (v0.1)

Method: on the running cluster, a namespace with an nginx pod and a Service, and a throwaway busybox client that requests the page with a 3 second timeout. First without any policy, then after applying a `NetworkPolicy` with an empty `podSelector` and `policyTypes: [Ingress]` (deny all ingress).

| Step | Result |
|---|---|
| Before the policy | The client received the nginx page. |
| After the policy | `wget: download timed out`. |

Limits: one namespace, ingress only, one run, and the client and server may have been on the same node. This does not prove egress rules, traffic between nodes or isolation between namespaces. The isolation tests cover those.

## Tenant baseline on the local cluster (v0.1)

Method: `helm template` for each sample tenant, applied with `kubectl apply`. Alpha produced 9 objects and bravo 8, because bravo has no viewer group. `kubectl describe resourcequota` for alpha showed the `small` tier with nothing used: 500m and 512Mi of requests, 1 CPU and 1Gi of limits, 10 pods, 5 services, 2 volume claims, and 0 node port and load balancer services.

## Access checks (v0.1)

Method: `kubectl auth can-i` with `--as=tester` and `--as-group=<group>`. This asks the authorizer of the API server what is allowed, and it does not perform the action. One run on Kubernetes v1.37.0.

| Identity | Question | Answer |
|---|---|---|
| group bound to the built-in `edit` role | delete network policies | yes |
| group bound to the built-in `admin` role | delete network policies | yes |
| group bound to the built-in `admin` role | create role bindings | yes |
| `alpha-admins` in `tenant-alpha` | create deployments | yes |
| `alpha-admins` in `tenant-alpha` | delete network policies | no |
| `alpha-admins` in `tenant-alpha` | delete resource quotas | no |
| `alpha-admins` in `tenant-bravo` | get secrets | no |
| `alpha-viewers` in `tenant-alpha` | get secrets | no |

## Isolation tests (v0.1)

Method: `make test-isolation` runs 27 checks against the local cluster with the two sample tenants. They perform real actions, and every "must be blocked" check also tests the text of the refusal. Access checks use impersonation (`--as` and `--as-group`) with real requests. Checks of platform controls use server-side dry-run deletes, which run the real authorization and change nothing. Network checks reach pods by IP, so DNS is not involved. The suite removes its test objects when it ends.

| Section | Checks | Result |
|---|---|---|
| Access: secrets across tenants, and viewers | 6 | all passed |
| Platform controls cannot be changed by a tenant | 5 | all passed |
| Network between tenants, same-tenant traffic and DNS | 5 | all passed |
| Noisy neighbour: CPU limit, memory limit, quiet tenant unaffected | 5 | all passed |
| Quota, services and default limits | 6 | all passed |

Three consecutive runs all passed. In each of them the CPU hog (limit 0.5 CPU) used 0.50 CPUs, measured as the difference in the cgroup `usage_usec` counter divided by the real elapsed time. The kernel reported 163, 161 and 165 throttled periods. The memory hog (limit 64Mi) ended with the reason `OOMKilled`. An earlier version of the script divided by a nominal 10 s and reported 0.53 CPUs, which was an error of the window, so it now uses timestamps.

Break test: all six network policies were deleted by hand and the suite was run again. Exactly two checks failed, "alpha client cannot reach the bravo server" and the reverse, each with "it succeeded, but it must be blocked". The other 25 still passed, including the same-tenant traffic, so the failures were caused by the missing policies and not by a broken network. After `make tenants-apply` the suite passed again.

Limits:

- The nodes are containers on one machine and share its CPU and memory. The noisy neighbour checks show that pod limits are enforced, not how the platform behaves when a node is full.
- The suite covers ingress and egress between two tenants by pod IP. It does not cover every possible path, for example traffic through a Service or through the host network.
- The expected refusal texts (for example "exceeded quota") were checked on Kubernetes v1.37.0 only.
- The suite does not run in CI yet. It needs a cluster, so it comes in a separate change.
