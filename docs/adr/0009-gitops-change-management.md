# ADR-0009: GitOps as the Declarative Change Management Mechanism

**Date:** 2026-03-09
**Status:** Accepted

## Context

Infrastructure and application configuration changes in production have historically been
applied via manual CLI commands, cloud console clicks, and ad-hoc scripts. This produces
configuration drift between the declared and actual state, a history that is not tied to
the change management process, and no built-in rollback mechanism.

Compliance requirements (SOC-2 Type II, change management controls) require:
- Every production change is approved before execution.
- Every change is attributable to a named actor.
- Every change has an audit trail.
- Rollback from any change is possible within a defined time window.

The change management system must not be a separate tool from the engineering workflow —
engineers should use the same PR and code review flow they already use for application code.

## Decision

We adopt GitOps as the change management mechanism for all infrastructure and application
configuration.

**Single source of truth:** The desired state of all infrastructure (Kubernetes manifests,
Helm values, Terraform/IaC modules, network policy, RBAC, secrets configuration) is declared
in version-controlled Git repositories. The actual state is continuously reconciled to match
the declared state by a GitOps controller (Flux or Argo CD).

**Approval gate:** Production changes require at least one PR approval from a person who is
not the PR author. CODEOWNERS enforces which teams must approve changes to which directories.
Merging to the production branch without approval is blocked by branch protection rules.

**Rollback plan requirement:** Every PR that changes production configuration must include a
documented rollback plan. For most changes, rollback is a `git revert` of the PR — this must
be explicitly verified and noted. Complex changes (multi-step migrations) must document the
specific revert or compensating change sequence.

**Drift detection and remediation:** The GitOps controller runs on a continuous reconciliation
loop (every 60 seconds). Out-of-band changes (applied directly via `kubectl`, console, or CLI)
are detected and reverted automatically. Out-of-band changes in production generate a security
alert and an audit log entry.

**Break-glass:** A documented break-glass procedure exists for production changes that must
bypass the GitOps pipeline (e.g., active incident requiring an immediate patch). Break-glass
requires: two senior engineers approving outside the normal flow, a pre-created incident record,
and a commit of the emergency change to the GitOps repository within 30 minutes of application.
Break-glass use is itself an audit event.

**Policy and compliance archive:** CTO-level policies and ARB architecture standards are
archived in the GitOps repository under `docs/policy/`. Historical versions are accessible
via Git history. The current version is queryable without a Git client via the repository's
published docs site.

## Consequences

**Positive:**
- Every production change is a Git commit — automatically timestamped, attributed, and linked
  to a PR with approval records.
- Rollback of any change is a `git revert` (or branch reset), which itself goes through the
  approval workflow.
- Drift detection means unauthorized or accidental out-of-band changes are reversed within
  60 seconds of detection.
- SOC-2 change management evidence is generated automatically from the Git and PR record.
- Developers use the same workflow (PR, review, merge) for infrastructure as for code —
  no separate ITSM ticket or change calendar.

**Negative:**
- GitOps adds latency to simple one-liner changes. Applying a single environment variable
  change requires a PR, approval, and reconciliation loop — minimum several minutes.
- The GitOps controller is a critical infrastructure component; its unavailability means
  changes queue but are not applied. Outage handling runbooks are required.
- Sensitive values (secrets) cannot be stored in Git in plaintext. Secrets management
  integration (sealed secrets, external secrets operator) adds implementation complexity.
- Break-glass procedures are genuinely harder to execute correctly under incident pressure.
  Regular drills and clear runbooks are required.
- Large monorepos with many teams sharing a GitOps repository require careful CODEOWNERS
  configuration to prevent accidental cross-team permission grants.

## Alternatives Considered

### ITSM-Based Change Management (ServiceNow, Jira tickets)
Changes are tracked in a ticketing system. Engineers apply changes manually or via runbooks
after ticket approval.

Rejected because: the ticket and the actual applied change are separate artifacts — the ticket
says what was requested, not what was done. Drift is invisible. Rollback requires manually
reversing the change, which is error-prone. Compliance evidence collection is manual.

### Immutable Infrastructure with Full Redeploys
Every change triggers a full infrastructure rebuild from scratch (immutable AMIs, full cluster
replacement).

Rejected for the primary change path because: rebuild cycles are too slow for configuration
changes; not all infrastructure is immutable by nature (databases, stateful services). GitOps
handles stateful configuration changes that cannot use immutable infrastructure patterns.

### Ansible / Chef / Puppet (mutable configuration management)
A configuration management agent applies desired state to running infrastructure.

Rejected because: these tools apply state to existing running systems (mutable), not declare
desired state in a version-controlled source of truth. Drift between the configuration tool's
state and Git is possible. The PR review workflow integration is weaker than GitOps.

### Manual Runbooks with CLI
Engineers follow documented runbooks to apply changes and log actions in an incident management
system.

Rejected because: runbook execution is error-prone and produces no structured audit trail;
drift between the runbook's expected state and actual state accumulates silently;
compliance evidence requires manual collection.