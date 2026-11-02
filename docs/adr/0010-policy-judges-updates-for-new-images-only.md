# 0010. The policy judges updates, but only for images that the old object did not have

- Status: accepted
- Date: 2026-11-02

## Context

The policy `disallow-latest-image-tag` (ADR 0009 describes its scope) first watched only the operation CREATE. A tenant admin can change objects after creating them, so a workload could start with a pinned image and be changed to `latest` afterwards.

Observed on 2026-11-02 on the local cluster (Kyverno v1.19.2, Kubernetes v1.37.0), each result from one run:

1. With CREATE only: a tenant admin created a pod with `busybox:1.36` and patched its image to `busybox:latest`. The API accepted the patch, and the pod then showed `busybox:latest`. For a Deployment, `kubectl set image` to `busybox:latest` was accepted and the spec showed `busybox:latest`. The old pod kept running `busybox:1.36`. The new ReplicaSet could not create its pod, and its Warning event carried the denial of the policy.
2. Adding UPDATE with an expression that read `oldObject.spec` failed offline: the Kyverno CLI gives an `oldObject` without `spec` on creation, and every failing pod ended with `no such key: spec`.
3. In the cluster, the same idea guarded with `has(oldObject.spec)` worked for pods. For Deployments, Kyverno rewrote the paths of the generated rule, and the creation of a Deployment with an unpinned image ended with `Policy disallow-latest-image-tag error: error: no such key: spec`. The Deployment was refused, but without the message that names the fix and the runbook.
4. A guard on `has(oldObject.metadata)` did not help. The generated rule showed it rewritten to `has(oldObject.spec.template.metadata)`, and the live check of the Deployment message failed again.
5. A guard on `request.operation == 'UPDATE'` was left unchanged in the generated rules (for Deployments the generated text starts with `request.operation == 'UPDATE' ?`). The offline suite passed, and the live script passed 21 of 21 checks, among them:
   - an unrelated change (a label) to a running pod, a Deployment and a CronJob that already use `busybox:latest` is allowed;
   - swapping the image of such a pod or CronJob for another `latest` image is denied, and so is changing the image of a Deployment to `latest`;
   - scaling that Deployment up is accepted, and the new `latest` pod is denied at the pod.
6. I did not try to express an update in a Kyverno test file. The offline tests use pods and the operation CREATE only.

## Options considered

1. **CREATE only.**
   - Pros: simple, and the offline tests cover it fully.
   - Cons: a pinned workload can be changed to `latest` afterwards (observation 1).
2. **UPDATE as well, with the same check on the whole object.**
   - Pros: no extra logic.
   - Cons: by the expression it would also deny unrelated edits of a workload that already runs `latest`, for example a label change. I did not test this variant live.
3. **UPDATE as well, judging only images that the old object did not have.**
   - Pros: closes the bypass, and workloads that were created before the policy stay maintainable.
   - Cons: it needs the old images, and the guard that reads them must survive the rewriting that Kyverno does for the generated rules (observations 3 and 4). It is tested live only, because the offline tests do not cover updates (observation 6).

## Decision

Use option 3, with the old images read only when `request.operation == 'UPDATE'`. A guard on the request has no object path that Kyverno can rewrite.

## Consequences

- A workload that already runs `latest` keeps running and accepts unrelated edits. A new pod of such a workload is a creation, so it is denied until the image is pinned. Scale-up is tested live. A node drain and a restart of such a pod were not tested, but they create a pod too.
- StatefulSets, DaemonSets and Jobs get the same generated rule. They are not tested live. Deployments and CronJobs are.
- Offline, only pods and creations are tested. Updates and the generated rules for other kinds are tested only by `tests/policy-live/run.sh`, and in CI by the `policy-live` job, which is not a required check yet. If a later Kyverno version changes the path rewriting, the live checks are what will show it. The Deployment message check failed on the two earlier guards.
- The runbook describes what a developer sees, including the hung rollout of a Deployment (the Warning event of its ReplicaSet).
- Revisit this decision if the Kyverno CLI can test updates offline, or if a future version changes how generated rules treat `request`.
