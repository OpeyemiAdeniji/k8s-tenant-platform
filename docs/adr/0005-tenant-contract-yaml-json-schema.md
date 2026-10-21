# 0005. Tenant contract as plain YAML with a JSON Schema

- Status: accepted
- Date: 2026-10-21

## Context

A team requests a tenant by adding one file in a pull request. That file is the interface between the tenant teams and the platform, so its format is a design decision.

The format must be simple for a developer to write and strict enough that mistakes are caught before merge, not in the cluster. It must be readable by an Argo CD ApplicationSet in v0.3, and it must be testable with examples that pass and examples that fail. It must also carry the labels for ownership and cost showback.

## Options considered

1. **Plain YAML file, validated with a JSON Schema in continuous integration**: one file per tenant in `tenants/`, checked by a script.
   - Pros: no extra component to run. The format is readable by an ApplicationSet files generator. The schema is machine-readable and can be used by editors. It is easy to test with valid and invalid examples.
   - Cons: JSON Schema cannot express rules that involve the file name or other files, so a small script checks that the name equals the file name. Validation happens in continuous integration only, so someone who creates resources directly in the cluster skips the contract. Admission policies in v0.2 are the second layer for that case.
2. **Kubernetes custom resource (a Tenant CRD) with a controller**: the API server validates the object and a controller creates the resources.
   - Pros: validation happens at the API, a status field can show readiness, and the controller keeps reconciling.
   - Cons: the controller must be built or installed, kept running and explained. It uses memory on a development machine with limited memory, and it hides what is created behind code. This project is meant to show how built-in Kubernetes controls fit together.
3. **Helm values file per tenant for a shared chart**: the contract is the `values.yaml` of a chart, with a values schema.
   - Pros: Helm is widely known, and a values schema is supported.
   - Cons: the contract becomes tied to the structure of the chart, and a team edits keys shaped by chart internals. How the resources are rendered from the contract is a separate decision, so the contract should not depend on it.

## Decision

Use a plain YAML file validated with a JSON Schema (Option 1). The schema is `schemas/tenant.schema.json`, and `scripts/validate_tenants.py` runs it in continuous integration.

- **Version:** `schemaVersion` is `1`. A change that would break existing files raises the version.
- **Strictness:** unknown fields are rejected, so a typo such as `sise` fails loudly.
- **Identity:** the `name` must equal the file name without `.yaml`. The namespace is `tenant-<name>`. Platform namespaces never start with `tenant-`, so a tenant cannot collide with them, and policies can match the prefix.
- **Size:** a tenant chooses `small`, `medium` or `large`, not raw CPU and memory. The quota values for each size are defined in a later change, after the capacity of the cluster has been measured. A custom size becomes a time-limited policy exception in v0.2.
- **Access:** `admins` and `viewers` are group names. A colon is not allowed, so built-in groups such as `system:masters` cannot be requested.
- **Labels:** `owner.team`, `costCentre` and `environment` become labels on every resource, which the cost showback in v0.3 uses.
- **Hostname:** no hostname field yet. A new optional field does not break existing files, and a larger change raises `schemaVersion`.
- **Tests:** `tests/contract/` holds files that must pass and files that must fail. Each invalid file states the message it must produce on its first line, so a file cannot fail for the wrong reason.

## Consequences

- A bad tenant file fails in the pull request, with a message that names the field and the allowed values.
- Two sample tenants, `alpha` and `bravo`, live in `tenants/`. They use `example.com` addresses and are not real teams. In v0.3 the ApplicationSet will create them on the local cluster.
- The contract is checked in continuous integration only. The admission policies in v0.2 and the isolation tests protect the cluster itself.
- The script has to be extended for any rule that needs more than one file, for example a name that is unique across all tenants. The file name rule already gives that for names.
- Revisit this decision if teams need to request things that do not fit a flat file, or if a controller with a status field would give better feedback than a pull request comment.
