# 0008. CEL-based Kyverno policies, and exceptions that expire through a TTL label

- Status: accepted
- Date: 2026-10-30

## Context

ADR 0004 chose Kyverno and listed what was not verified. Installing Kyverno v1.19.2 (chart 3.9.2) changed two assumptions of that ADR. The install notes say that the legacy policy types (`ClusterPolicy`, `Policy`, `CleanupPolicy` and the `kyverno.io` PolicyException) are deprecated, and the migration guide of the v1.19 documentation says that they will be removed in v1.20. The same notes say that PolicyExceptions are disabled by default.

The requirement from the problem statement is that every exception carries an expiry and stops applying by itself.

Observed on this cluster on 2026-10-30 (kind v0.33.0, Kubernetes v1.37.0, Calico v3.33.0, Kyverno v1.19.2), each result from a single run:

1. The cluster serves `policies.kyverno.io/v1` for `ValidatingPolicy`, `NamespacedValidatingPolicy`, `DeletingPolicy` and `PolicyException`. The legacy kinds in `kyverno.io` still exist.
2. A throwaway `ValidatingPolicy` with a `namespaceSelector` became ready within 15 seconds and denied a pod with the image tag `latest` in a tenant namespace. The denial came from the Kyverno webhook `vpol.validate.kyverno.svc-fail`. No Kubernetes ValidatingAdmissionPolicy was generated for it, because only the one from Calico was listed.
3. An exception that carries a CEL condition with `time.now()` is rejected when it is created: `undeclared reference to 'time'`. The environment of an exception's `matchConditions` has no `time` library in this version, although plain CEL conditions compile there.
4. With exceptions enabled (`--enablePolicyException=true` and `--exceptionNamespace=platform-exceptions`), the pod that had been denied was created while an exception for it existed, and it was denied again after the exception was deleted.
5. The label `cleanup.kyverno.io/ttl: 3m` on an exception: created at 12:51:56 UTC, deleted at 12:54:56 UTC according to the log of the cleanup controller.
6. The cleanup controller was not allowed to delete PolicyExceptions or ConfigMaps (`kubectl auth can-i` answered `no`). After a ClusterRole for `policyexceptions` in `policies.kyverno.io` (get, list, watch, delete) it answered `yes`, and deletion worked.
7. The label with an absolute date (`2026-10-30T125935Z`, no colons because a label value cannot contain them): the exception was deleted at 12:59:35 UTC. A date one hour in the past: deleted within about one second of creation.

## Options considered

1. **A time condition inside the exception**: the exception stops matching after a date, and nothing is deleted.
   - Pros: no extra controller and no extra permission.
   - Cons: rejected by the API in this version (observation 3).
2. **The TTL label with a duration** (`cleanup.kyverno.io/ttl: 2h`).
   - Pros: it works (observation 5), and it is easy to read.
   - Cons: the duration counts from the creation of the object. With a GitOps controller that restores deleted objects (planned for v0.3), a deleted exception would be created again with a new timer, and it would never expire. This is expected and has not been tested.
3. **The TTL label with an absolute date** (`cleanup.kyverno.io/ttl: 2026-12-01T000000Z`).
   - Pros: it works (observation 7). A recreated expired exception is deleted again within about a second, so the date cannot be reset by recreating the object.
   - Cons: the format is harder to read than a duration, and it needs a helper and a check in continuous integration. Between recreation and deletion the exception may be active for about a second.
4. **A scheduled `DeletingPolicy`** that deletes exceptions whose date has passed.
   - Pros: the rule is visible as a policy.
   - Cons: not tried. It needs the same permission to delete exceptions, and a schedule adds delay.

## Decision

- Policies are written as `ValidatingPolicy` (`policies.kyverno.io/v1`). Legacy `ClusterPolicy` objects are not written. `kyverno test` runs with `--warnings-as-errors` in continuous integration, so a legacy type cannot enter.
- Exceptions are `PolicyException` objects of `policies.kyverno.io/v1`, honoured only in the namespace `platform-exceptions`. Tenants have no rights there.
- Every exception carries `cleanup.kyverno.io/ttl` with an **absolute date** (option 3). Continuous integration will refuse an exception file without one, and one whose date has passed.
- The Kyverno cleanup controller gets one ClusterRole to delete PolicyExceptions (`platform/kyverno/cleanup-clusterrole.yaml` and `cleanup-clusterrolebinding.yaml`), applied by `make kyverno-up` before the install.

## Consequences

- In the observed runs, exceptions disappeared at the second of the date that the label named, and the next admission after the deletion was denied. These are three samples for the deletion and one for the denial, so they show that it works, not how reliable it is.
- Not verified yet, and each item needs a test: a TTL of days; whether a pending expiry survives a restart of the cleanup controller; what happens while the cleanup controller is down (the exception would outlive its date); whether a fresh install with the grant in place needs no restart; the recreation of an exception by Argo CD; and the failure behaviour of the admission webhook while Kyverno is down. The name `vpol.validate.kyverno.svc-fail` suggests that matched requests are refused, and that has not been checked.
- A developer sees the text of Kubernetes and Kyverno before the policy message: `admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy <name> failed: <message>`. Only the message itself can be written for the developer.
- The log of the Kyverno cleanup controller prints deprecation warnings about the legacy cleanup kinds. They come from Kyverno itself.
- Revisit this decision if Kyverno changes or removes the TTL label, if the cleanup controller cannot be given this permission in another environment, or if exceptions need a reason or an approver that a label cannot hold.
