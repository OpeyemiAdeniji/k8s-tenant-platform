# 0011. What the guardrail does while Kyverno is stopped, crashes or restarts

- Status: accepted
- Date: 2026-11-02

## Context

ADR 0009 and the runbook said that a policy webhook with the failure policy `Fail` makes the platform fail closed when Kyverno is down. I read that from the webhook configuration while Kyverno was running, and the runbook admitted that it was not tested. It was then tested, and the result differs.

Observed on 2026-11-02 on the local cluster (Kyverno v1.19.2, Kubernetes v1.37.0, one admission controller replica), each result from one run unless the text says otherwise:

1. **Orderly stop (scale to zero).** Within 5 seconds the five webhook configurations of the service `kyverno-svc` were removed. Only the two of the cleanup controller stayed, and they were still the only ones 30 seconds later. The endpoint list of `kyverno-svc` was empty. After the restart all eight configurations were back, with `vpol` and `Fail`, and the service had a new endpoint address.
2. **While stopped.** A tenant admin created a pod with `busybox:latest` in `tenant-alpha`, which is denied when Kyverno runs. In a second run, a tenant admin created a pod with a pinned image and patched its image to `busybox:latest`, and the API accepted both. Pods in `default` and `kube-system` were created too (pinned images). After the restart, a `latest` pod was denied with the message of the policy. Kyverno was back after 26 seconds in the first run, and the second rollout also finished.
3. **Crash of the container process** (`crictl stop -t 0` on the node). The webhook configuration was still there. For the first four probes (19:29:36 to 19:29:43 UTC, every 2 seconds, as a tenant admin, as server-side dry runs) both a pinned and a `latest` pod were refused with a webhook error. From 19:29:46 the pinned pod was admitted and the `latest` pod was denied by the policy. The container restarted in place (1 restart). Only `tenant-alpha` was probed.
4. **Rolling restart** of the admission deployment: 45 probes of a `latest` pod over about 100 seconds (19:34:22 to 19:36:03 UTC) were all denied. None was admitted or refused.
5. **A tenant admin trying to switch the guardrail off.** Four real requests were refused with `Forbidden`: scaling the admission deployment to zero (refused at the read of the deployment), the same as a patch, deleting the admission pod, and deleting the webhook configuration. They were server-side dry runs.
6. I did not look at which process removes the webhooks in observation 1, or whether the start argument `--autoUpdateWebhooks=true` controls it.

## Options considered

1. **Accept it and document exactly what was observed.**
   - Pros: no extra component, no extra memory, and the repair is a restart of one pod. The window requires rights that a tenant admin did not show in four attempts.
   - Cons: the guardrail is off while Kyverno is stopped on purpose. A `latest` workload that is created in that window keeps running.
2. **Detect it afterwards** with Kyverno's reports.
   - Pros: it makes the gap visible.
   - Cons: not tried. I do not know whether the reports flag a `latest` workload that was admitted during an outage. It detects, and does not prevent.
3. **Enforce the rule inside the API server** with a native `ValidatingAdmissionPolicy` (option 3 of ADR 0004).
   - Pros: no webhook, so no outage window.
   - Cons: a second policy language, without Kyverno's messages and exceptions. Not tried here.

Two replicas of the admission controller were also considered. They would cost memory (Kyverno used about 0.5 GiB with one replica of each component), and I did not test whether one stopping pod would still remove the webhooks.

## Decision

Use option 1. The runbook states the observed behaviour. It is the choice that I recommended, and it was chosen on 2026-11-02.

The statements that ADR 0009 made about an outage ("could block system pods whenever Kyverno is down" and the weight that its observation 6 gives to the failure policy) are amended by this ADR. The decision of ADR 0009, scoping by label, stands.

## Consequences

- The guardrail protects against mistakes, and not against someone who stops Kyverno on purpose. Only the platform team can do that, as far as the four requests show.
- Not tested: a Helm upgrade, a node drain, two replicas, and whether a `latest` workload created during a stop appears in Kyverno's reports. A drain with one replica probably leaves a gap, and I did not test it.
- The crash result is one sample, and the probe measured pod creation in tenant namespaces only.
- Follow-ups, if the guardrail has to become a security boundary: the reports as detection (option 2), a native policy (option 3), or two replicas.
- Revisit this decision if tenants get rights in the `kyverno` namespace, or if a Kyverno upgrade changes how webhooks are removed.
