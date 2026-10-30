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
| 3 | 44 s | 204 s | Run on 2026-10-30 after the machine had been idle for four days. Whether the images were still on disk was not checked. |

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

## Isolation tests, first version with 27 checks (v0.1)

This version was superseded by the version with node placement below. It is kept because its results were measured.

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
- The network checks show that traffic between two tenants is blocked by pod IP. They do not show whether the ingress rules or the egress rules did it, because the policies deny both directions at once. Traffic through a Service or through the host network is not covered.
- The expected refusal texts (for example "exceeded quota") were checked on Kubernetes v1.37.0 only.
- The suite runs in CI in the `isolation` job. See the section on the CI runs below.

## CI isolation job on a GitHub runner (v0.1)

Method: the `isolation` job installs pinned kind, kubectl and Helm with `scripts/install-tools.sh`, then runs `make cluster-up`, `make tenants-apply` and `make test-isolation`, which are the same scripts as a local run. The step durations below come from the step timestamps of one passing run (40339094821, commit cb4bf80), read with `gh run view --json jobs`. The resolution is one second.

| Step | Duration |
|---|---|
| Set up job | 0 s |
| Run actions/checkout@v4 | 1 s |
| Install pinned tools | 2 s |
| Build the cluster | 121 s |
| Apply the tenants | 1 s |
| Run the isolation tests | 32 s |
| Show the cluster state after a failure | 0 s |
| Post Run actions/checkout@v4 | 0 s |
| Complete job | 0 s |

The times of every run of the job are listed in the section on the CI runs below.

Runner as read from the diagnostics of a failed run: kernel 7.0.0-1017-azure, Kubernetes v1.37.0 and containerd 2.3.4. The local machine has kernel 6.18.54.1-microsoft-standard-WSL2 with the same Kubernetes and containerd versions.

Memory check line of the passing run: `pass  the memory hog was killed by SIGKILL (exit code 137) and not evicted; this cluster reports the reason 'Error' and not OOMKilled`

The first two runs failed at the memory check. The details are in `docs/runbooks/isolation-job-failed.md`.

Pod placement is decided by the scheduler and the test does not control it. Locally and in the first CI run all four test pods ran on one node. In the passing run the diagnostic line was: `nodes: alpha server on tenant-platform-worker2, alpha client on tenant-platform-worker2, bravo server on tenant-platform-worker2, bravo client on tenant-platform-worker`. So the network checks cover traffic between nodes only by chance, and they are not a guarantee. This was fixed afterwards by placing the test pods on named nodes, see the section on node placement below.

## Isolation tests with node placement (v0.1)

Method: the suite places the test pods on named nodes with a `nodeSelector` on `kubernetes.io/hostname`. Node 1 is `tenant-platform-worker` and node 2 is `tenant-platform-worker2`. Each tenant gets a server and a client pod on each node, which makes eight pods. A check reads the node of every pod and fails if one is not where it should be, so a case cannot be reported as covered when the scheduler put the pod elsewhere. The two hog pods of the noisy neighbour section run on node 1, next to the bravo server that must keep answering.

| Section | Checks |
|---|---|
| Access: secrets across tenants, and viewers | 6 |
| Platform controls cannot be changed by a tenant | 5 |
| Network: placement (1), same tenant on the same node and across nodes (4), DNS (1), different tenants blocked on the same node and across nodes (8) | 14 |
| Noisy neighbour | 5 |
| Quota, services and default limits | 6 |
| Total | 36 |

Result: one full run after the restore passed 36 of 36 (`all isolation tests passed`). An earlier run showed the whole network section passing line by line.

Break test: all six network policies were deleted by hand and the suite was run again. Exactly the eight checks that must be blocked failed, four on the same node and four across nodes, each with "it succeeded, but it must be blocked". Eight of 36 failed in total, so the other 28 checks did not fail, including the placement check and the same-tenant checks. After `make tenants-apply` the suite passed again.

Quota margin: in the noisy neighbour section the CPU limits in `tenant-alpha` add up to 1000m, which is the whole `limits.cpu` of the small tier (four test pods at 100m, the CPU hog at 500m and the memory hog at 100m). The suite passed, so a quota accepts a total equal to its limit. There is no margin, so one more pod in that section would be rejected.

Limits: the network checks show that traffic between two tenants is blocked. They do not show whether the ingress rules or the egress rules did it, because the policies deny both directions at once.

## CI runs of the isolation job (v0.1)

Method: `gh run list --workflow CI` for the whole run, and `gh pr checks` for the `isolation` job alone. There are six runs, so this file gives the range and no average.

| Run | Trigger | Result | Whole run | isolation job |
|---|---|---|---|---|
| 40332877934 | pull request 9, first push | red | 2m35s | 2m30s |
| 40337348572 | pull request 9, extra diagnostics | red | 2m12s | 2m7s |
| 40339094821 | pull request 9, accept exit code 137 | green | 2m45s | 2m40s |
| 40342841955 | pull request 9, runbook | green | 2m11s | 2m6s |
| 40343518404 | merge to `main` | green | 2m17s | not read |
| 40347437658 | pull request 10, node placement | green | not read | 2m53s |

The whole run took between 2m11s and 2m45s in the five runs where it was read, and the `isolation` job between 2m6s and 2m53s in the five runs where it was read. The two red runs failed at the memory check, see `docs/runbooks/isolation-job-failed.md`.

## Kyverno install (v0.2)

Method: `make kyverno-up` runs `helm upgrade --install` with `--wait` for the pinned chart version, which is chart 3.9.2 with Kyverno v1.19.2 (`platform/kyverno/chart-version`). It uses the stock values, so nothing is tuned. The readings were taken on the running cluster with both sample tenants applied. The first set was taken before the install, and the second about six and a half minutes after it. `free -h` rounds to 0.1 GiB, so each difference has an uncertainty of about 0.1 GiB. The two readings are 12 minutes apart on a machine with other activity, so drift between them cannot be excluded. Each result is one sample.

| Reading | Before Kyverno | With Kyverno |
|---|---|---|
| `free -h`, used | 2.6 Gi | 3.1 Gi |
| `free -h`, available | 5.1 Gi | 4.5 Gi |
| `docker stats --no-stream`, three nodes added up | 3.962 GiB | 4.512 GiB |
| Pods in the cluster | 24 | 28 |

The cost of Kyverno is about 0.5 GiB by `free -h` and 0.55 GiB by `docker stats`. The two sources agree this time, unlike the cluster measurement above. The chart installed four deployments with one replica each: admission, background, cleanup and reports controllers. The install notes of the chart warn that one admission replica is not a high availability setup. This is accepted for a one-machine reference.

Install time: `kyverno ready: 100 s` from the script, which includes pulling images. Whether the images were already on disk was not checked.

Isolation suite with Kyverno installed: 36 of 36 checks passed. No policy was defined yet, so Kyverno had nothing to evaluate. This shows that the installation does not interfere with the suite. It does not show that policies will not.

## Policy exceptions that expire (v0.2)

Method: on the local cluster (Kyverno v1.19.2, chart 3.9.2) a throwaway `ValidatingPolicy` denied pods with the image tag `latest` in tenant namespaces. `PolicyException` objects (`policies.kyverno.io/v1`) in `platform-exceptions` carried a `cleanup.kyverno.io/ttl` label. The deletion times are the lines `resource has been deleted` in the log of the cleanup controller. The polling column comes from a loop that checks every 5 seconds. Each row is one sample.

| Label value | Created (UTC) | Deleted according to the controller log (UTC) | Polling loop |
|---|---|---|---|
| `3m` | 12:51:56 | 12:54:56 | gone after 183 s |
| `2026-10-30T125935Z` (about 2 minutes ahead) | about 12:57:35 | 12:59:35 | gone after 119 s |
| `2026-10-30T115735Z` (about 1 hour in the past) | about 12:57:35 | 12:57:36 | gone after 1 s |

Other results from the same experiments:

- A condition with `time.now()` in the `matchConditions` of an exception was rejected when the exception was created: `undeclared reference to 'time'`.
- With an active exception, a pod with `busybox:latest` was admitted. After the exception had been deleted, the same pod was denied. One sample each.
- Before the grant, `kubectl auth can-i delete policyexceptions.policies.kyverno.io` for the cleanup controller answered `no`. After it, `yes`.

Limits: three expiry samples, a longest TTL of three minutes, and a cluster that was running while the grant was added. The behaviour after a restart of the controller, with TTLs of days, and on a fresh install has not been tested.
