# 0004. Kyverno as the admission policy engine

- Status: accepted
- Date: 2026-10-30

## Context

The platform must reject unsafe workloads when they are submitted, with a message written for the developer: what is wrong, how to fix it, and a link to a runbook. Each policy must have passing and failing cases that run in continuous integration. A policy exception must carry an expiry and stop applying by itself. The tenants are internal teams (ADR 0001), and the whole platform has to fit on one machine with 7.7 GiB of memory, of which the cluster already uses about 1.8 GiB (`docs/measurements.md`).

Observed on this cluster (Kubernetes v1.37.0): when Calico was installed, the output listed MutatingAdmissionPolicy, ValidatingAdmissionPolicy and their bindings as created. So the built-in admission policies of Kubernetes are available here without any extra component, and any engine that is chosen has to live next to Calico's own policies.

The comparison below comes from reading documentation on 2026-10-26. None of it has been tried on this cluster yet.

## Options considered

1. **Kyverno**: policies are Kubernetes objects written in YAML, and a rule has a `message` field.
   - Pros: `kyverno test` runs the cases that are declared in a `kyverno-test.yaml` file against the policies, with expected results of pass or fail, and it needs no cluster. The same command can test ValidatingAdmissionPolicies. A PolicyException object exists, and the reserved label `cleanup.kyverno.io/ttl` makes the cleanup controller delete a labelled resource after a time. That is a candidate for exceptions that expire.
   - Cons: it is an extra component with its own webhook, and its memory use on this machine has not been measured. The cleanup controller needs permission to delete each kind of resource that it manages, and whether it can delete a PolicyException has not been tried. Kyverno has more than one policy type, so the one to use has to be chosen against the version that is installed. The engine becomes a dependency of every admission request that it matches, so its failure behaviour has to be chosen on purpose.
2. **OPA Gatekeeper**: policies are a ConstraintTemplate plus a Constraint, written in Rego or in CEL.
   - Pros: a mature project with its own test command (`gator`). Its CEL validation of Kubernetes admission policies is documented as stable since v3.18, and it can generate ValidatingAdmissionPolicy objects for the in-process path.
   - Cons: two objects per policy, and Rego is a language of its own to learn and review. I did not find a mechanism for exceptions that expire in the documentation that I read. That is not proof that none exists. The requirement in the problem statement names `kyverno test`, so this option would also change the stated test approach.
3. **Built-in ValidatingAdmissionPolicy only**: policies are CEL expressions, with a binding object that activates each one.
   - Pros: no extra component to run, evaluated inside the API server, generally available since Kubernetes 1.30, and `messageExpression` can build the failure message from the request and from parameters.
   - Cons: no exception object and no expiry. The tests would have to apply the policy to a cluster or use another tool. CEL expressions are harder for a platform team to read than YAML patterns. It validates, and the rest of this plan does not need more.

## Decision

Use Kyverno (Option 1).

- Every policy has a `kyverno-test.yaml` with at least one passing case and one failing case, and `kyverno test` runs in continuous integration.
- Every rejection message states the problem, the fix and a runbook link.
- Exceptions use the PolicyException object with a `cleanup.kyverno.io/ttl` label, if the test below shows that the cleanup controller can delete it. If it cannot, this decision is revisited.
- The built-in ValidatingAdmissionPolicy stays available for a simple rule where an extra engine is not worth its cost. Calico's own policies are left alone.
- Kyverno is installed with Helm at a pinned version. The version, the memory it adds and the start time are measured and recorded in `docs/measurements.md`.

## Consequences

- Not verified yet, and each item gets a test: the memory that Kyverno adds on this machine; whether the cleanup controller can delete a PolicyException on its TTL; what a developer sees when a request is rejected; what happens to requests while Kyverno is down; and whether Kyverno's webhooks interfere with Calico or with the isolation suite.
- Kyverno becomes part of the platform to upgrade and to monitor.
- Kyverno should not apply to its own namespace or to `kube-system`, so those are excluded on purpose.
- Revisit this decision if Kyverno does not fit in the memory of this machine next to Argo CD and monitoring, if exceptions cannot be made to expire, or if the policy types of Kyverno change in a way that breaks the tests.

## Sources read

- Kyverno CLI test: https://kyverno.io/docs/kyverno-cli/usage/test
- Kyverno cleanup policies and the TTL label: https://main.kyverno.io/docs/policy-types/cel-policies/cleanup-policy
- Gatekeeper and the Kubernetes Validating Admission Policy: https://open-policy-agent.github.io/gatekeeper/website/docs/validating-admission-policy
- Kubernetes ValidatingAdmissionPolicy: https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/
