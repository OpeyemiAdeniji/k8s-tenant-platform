# 0009. Scope policies to tenant namespaces by label, and test the scope offline with a values file

- Status: accepted
- Date: 2026-10-30

## Context

A policy that denies pods must apply to tenant namespaces only. The platform namespaces (`kube-system`, `kyverno`, `calico-system` and others) run images that the tenant rules should not judge. The policy webhook of Kyverno has the failure policy `Fail` (observed below), so a policy that reaches system namespaces could block system pods whenever Kyverno is down.

The first policy, `disallow-latest-image-tag`, is the test case for this decision.

Observed on 2026-10-30 (Kyverno CLI and cluster v1.19.2, Kubernetes v1.37.0), each result from a single run:

1. The policy selects tenant namespaces with a `namespaceSelector` on the label `app.kubernetes.io/managed-by: k8s-tenant-platform`, which the tenant chart sets on every tenant namespace. The offline `kyverno test` of this policy reported 7 passed tests, and every row had the reason `Excluded`. The CLI has no namespace labels, so it excluded every pod, and it reports an excluded resource as a pass for any expectation, including for the pods that must fail.
2. Adding Namespace objects with the label to the test resources changed nothing. All pods stayed excluded.
3. A values file with the header `apiVersion: cli.kyverno.io/v1alpha1` and `kind: Values`, passed through the key `variables:` of the test file, gave the namespace its label. The seven tenant pods were then judged (`Ok`), and the pod in `kube-system` stayed `Excluded`. The file that `kyverno create values` writes has no header, and the CLI rejects it as a deprecated schema.
4. With the label supplied, removing the `latest` check from a copy made exactly two tests fail (`fail-latest-tag` and `fail-init-container-latest`) and gave a non-zero exit code. Without the label, the same removal gave exit code 0 and no failing rows.
5. Live, on the cluster, the policy was ready after 7 seconds. A pod with `busybox:latest` was denied in `tenant-alpha` with the message of the policy, including the fix and the runbook link. A pod with `busybox:1.36` was created there, and a pod with `busybox:latest` was created in `default`.
6. The webhook that Kyverno generated for the policy has the failure policy `Fail`, and a namespace selector with the label above, plus `NotIn` conditions for `kube-system` and `kyverno`. I did not set those two exclusions, and I did not look up where they come from. After the policy was deleted, that webhook was no longer listed. The other resource webhook that remained selects only objects with the label `generate.kyverno.io/policy-name`.

## Options considered

1. **A `namespaceSelector` on the label that the chart sets.**
   - Pros: the selector becomes part of the webhook, so requests from other namespaces never reach Kyverno (observation 6). It is the same label that the cost showback and the ownership use.
   - Cons: the offline test cannot see it unless a values file supplies the label (observations 1 and 2), and the file is written by hand, so it can drift from the chart.
2. **A CEL condition on the namespace name in `matchConditions`** (for example the prefix `tenant-`, which ADR 0005 reserves).
   - Pros: the offline test can see a namespace name.
   - Cons: the release notes of Kyverno 1.16 say that these conditions are evaluated by Kyverno and are not used to build the webhook's own conditions. If that holds for this version, the webhook would receive every pod creation in the cluster, and with the failure policy `Fail` an outage could block system pods. This was not tested.
3. **No scoping.**
   - Pros: nothing to maintain.
   - Cons: the tenant rules would judge system pods.

## Decision

Use the label selector (option 1).

- Every policy that applies to tenants has a `namespaceSelector` on `app.kubernetes.io/managed-by: k8s-tenant-platform`.
- The offline tests give the test namespace that label through `values.yaml` (with the header), and include one pod in `kube-system` that must stay `Excluded`.
- `scripts/policy-test.sh` guards against a false green. It checks that the table has the expected number of rows, that the only `Excluded` rows are the resources named `outside-`, that every failing pod carries the fix and the runbook link, that the runbook file exists, that the label which the policy selects on appears in the chart template, and that removing the `latest` check from a copy fails exactly the two expected pods. Broken copies of the policies were used to see each guard fail.
- A `policy` job in continuous integration runs `make policy-test`.

## Consequences

- The three expected counts in `scripts/policy-test.sh` have to be updated when test pods are added or removed.
- The test covers one tenant namespace (`tenant-alpha`) with the label that the chart sets today. The check on the chart template proves that the label text exists in `_helpers.tpl`. It catches a rename of that label, and not a change in how the chart applies it.
- Not tested: what happens to pod creation while Kyverno is down. The configuration suggests that only tenant namespaces would be blocked, but I have not stopped Kyverno to see it. Also not inspected: the rules of the other Kyverno webhooks, which have an empty namespace selector and are named after Kyverno's own objects.
- The policy was applied to the cluster only for the live test and then deleted. Installing it by `make kyverno-up`, and tests in the isolation suite, come in the next change.
- Revisit this decision if a future Kyverno version lets the offline CLI read namespace labels from the test resources, or if `matchConditions` become part of the webhook.
