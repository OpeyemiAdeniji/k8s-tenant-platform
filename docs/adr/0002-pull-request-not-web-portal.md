# 0002. Pull request as the self-service interface, not a web portal

- Status: accepted
- Date: 2026-10-21

## Context

Teams must be able to request a tenant without a ticket and without waiting for the platform team to do manual work. Something has to be the interface through which they ask, and through which the platform team reviews and approves.

The platform is built and maintained by one person. It has no real tenants, and it runs on one development machine with limited memory. The interface must give review, an audit trail and automatic validation, and offboarding must also be possible from it.

## Options considered

1. **Pull request that adds one tenant file**: a team adds `tenants/<name>.yaml`. Continuous integration validates it against the contract (ADR 0005) and a reviewer merges it.
   - Pros: nothing extra to build, host or secure. Git gives review, history, blame and revert for free. The merge is the approval step, so it replaces the ticket. Validation runs in the same place as the review. Rolling back is a Git revert. A team already knows this workflow from its own code.
   - Cons: the team needs a GitHub account and basic Git knowledge. There is no guided form, so errors are shown as CI messages and not as form fields. It is less friendly for people who do not use Git.
2. **Web portal that creates tenants through an API**: a form collects the request, and a backend creates the resources.
   - Pros: guided input with immediate feedback, a familiar experience for non-developers, and room for a status page.
   - Cons: it needs a frontend, a backend, authentication and a database or state store, and each of those must be built, secured and maintained. The portal then becomes a second source of truth unless it writes to Git as well. Review and audit have to be rebuilt. It uses time and memory that the project should spend on isolation, policy and measurement.
3. **Backstage or another developer portal**: a software template creates the repository change or the resources.
   - Pros: a mature framework with templates, a catalogue and plugins, and many organisations already use it.
   - Cons: it is a large application to install, configure and keep updated, and it needs a database and authentication. It would use a large share of the memory on this machine for a feature that the pull request already covers. It would also make the project about the portal and less about the platform.

## Decision

Use a pull request as the interface (Option 1). A tenant is requested by adding one file, changed by editing it, and offboarded by deleting it.

- Continuous integration validates the file against the contract and, from v0.3, posts a preview comment that shows what will be created.
- Merging into `main` is the approval, and the ruleset requires a pull request and green checks.
- Git history is the audit trail of who asked for what, who approved it and when.
- No web portal and no Backstage are built in this project.

## Consequences

- There is no user interface of our own. The interface is the diff, the preview comment and the CI checks. Dashboards in v0.3 are read-only views, and Argo CD provides its own interface for sync status.
- Tenant teams need to work with Git. This is accepted for the audience of this project, which is application developers.
- The tenant file is the API. A portal could later be a thin form that opens the same pull request, without any change to the platform. That is a possible future step and not a plan.
- Revisit this decision if the users are not comfortable with Git, if many requests need a guided flow, or if approvals need a workflow that pull requests cannot express.
