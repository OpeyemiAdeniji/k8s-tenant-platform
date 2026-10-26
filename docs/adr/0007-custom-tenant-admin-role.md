# 0007. A custom role for tenant admins instead of the built-in roles

- Status: accepted
- Date: 2026-10-26

## Context

Tenant admins must be able to run and change workloads in their namespace. They must not be able to change the controls that the platform put there, because the isolation claim of ADR 0001 depends on those controls staying in place. The default-deny network policy is the clearest case. A tenant that can delete it is no longer isolated.

Kubernetes ships the cluster roles `edit` and `admin`, which are meant to be bound inside a namespace. On the local cluster (Kubernetes v1.37.0) a group was bound to each of them with a role binding, and the question "may this group delete network policies" was asked with `kubectl auth can-i`. The answer was yes for `edit` and yes for `admin`. The group bound to `admin` could also create role bindings, so it could give other groups access to the namespace on its own.

## Options considered

1. **Built-in `edit` role**: tenant admins can change workloads.
   - Pros: nothing to maintain, and it is the usual choice.
   - Cons: measured on this cluster, it allows deleting network policies.
2. **Built-in `admin` role**: tenant admins can also manage access.
   - Pros: nothing to maintain.
   - Cons: measured on this cluster, it allows deleting network policies and creating role bindings. A tenant could grant access to people that the tenant file does not list.
3. **Custom `Role` created by the chart**: it allows workloads, services, config, secrets and volume claims, and it only reads quotas, limit ranges, events and network policies.
   - Pros: tenant admins cannot change platform controls, and the file is the only place where access is granted.
   - Cons: the role has to be maintained. When a new resource kind is needed, for example an Ingress, the role must be extended. It allows `pods/exec` and secrets in the tenant's own namespace.
4. **Built-in role plus an admission policy that protects the platform objects**.
   - Pros: it keeps the built-in role and blocks changes to objects that carry the platform label.
   - Cons: it needs the policy engine, which arrives in v0.2, and it hides the rule in a policy. It is useful as a second layer on top of Option 3.

## Decision

Use a custom role (Option 3) for tenant admins, and the built-in `view` role for viewers. The role is `tenant-admin`, and the chart binds it to the groups in `access.admins`. The built-in `view` role is bound to the groups in `access.viewers`, and it does not include secrets.

Authorization checks on the local cluster, asked with `kubectl auth can-i`, gave these answers:

| Identity | Question | Answer |
|---|---|---|
| admin group of tenant alpha | create deployments in `tenant-alpha` | yes |
| admin group of tenant alpha | delete network policies in `tenant-alpha` | no |
| admin group of tenant alpha | delete resource quotas in `tenant-alpha` | no |
| admin group of tenant alpha | get secrets in `tenant-bravo` | no |
| viewer group of tenant alpha | get secrets in `tenant-alpha` | no |

## Consequences

- A tenant cannot remove its own default-deny policy, its quota or its limits, and it cannot grant access to anyone. Access changes go through a pull request on the tenant file.
- These are authorization checks. They show what the API server would allow and they do not perform the action. The isolation tests in v0.1 perform the real actions.
- Tenant admins can run commands in their pods and read secrets in their own namespace. This is accepted for internal teams, as described in ADR 0001.
- The role has to be extended when the platform offers new resource kinds, for example when an ingress controller is added.
- An admission policy that protects the platform objects is added in v0.2 as a second layer.
- Revisit this decision if teams need to manage access themselves, or if the maintenance of the role becomes a burden.
