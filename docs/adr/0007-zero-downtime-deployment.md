# ADR-0007: Zero-Downtime Deployment via Blue/Green and Canary

**Date:** 2026-03-09
**Status:** Accepted

## Context

Production deployments have historically caused brief service interruptions during pod restarts
and connection draining. As the platform serves more traffic and upstream consumers have stricter
SLA requirements, even brief interruptions are unacceptable.

Zero-downtime deployment requires coordination across four dimensions:
1. Traffic — requests must not be dropped mid-deployment.
2. API compatibility — old clients must be served correctly while new code is rolling out.
3. Schema — database and event schemas must be readable and writable by both old and new code
   simultaneously during the transition window.
4. Feature gates — new behavior must be controllable independently of the artifact version
   so that partially rolled-out features can be toggled without a rollback.

## Decision

All production services support zero-downtime deployment using a combination of:

**Traffic shaping (rolling or blue/green):**
The service mesh or load balancer gradually shifts traffic from the old version to the new version.
Kubernetes rolling updates with `maxSurge: 1` and `maxUnavailable: 0` is the default. Blue/green
is used for services where instant switchover or instant rollback is required (e.g., after a
failed canary). Hard cutovers (terminate all old pods, start all new pods) are prohibited in
production.

**Canary releases:**
Traffic is shifted incrementally: 1% → 5% → 25% → 100%, with automated metric comparison at
each step. If error rate or latency of the canary exceeds the baseline by a defined threshold,
traffic shifts back automatically and an alert fires. Canary percentage and promotion thresholds
are configured per service in the deployment manifest.

**API backward compatibility:**
No breaking API changes are introduced during a deployment window. If a breaking change is
necessary, a new versioned API endpoint is introduced while the old version is maintained.
Old versions are deprecated on a defined timeline (minimum 6 months for external APIs).
See ADR on API versioning for the full lifecycle policy.

**Schema migration (phased, non-breaking):**
Database and event schema changes follow a phased approach:
1. Deploy Phase 1: add new column/field, backward-compatible with old code (old code ignores it).
2. Deploy Phase 2: new code writes both old and new; application is verified stable.
3. Run data backfill/migration.
4. Deploy Phase 3: remove old column/field only after no old code is running.

No schema change that makes existing data unreadable by the currently deployed version may be
applied until that version is fully retired.

**Feature flags:**
New behavior is gated behind feature flags managed in the central feature flag service.
Flags allow enabling or disabling behavior per tenant, per region, or per percentage of traffic
independent of the artifact version. A feature can be enabled for 10% of users without rolling
back the artifact. Flags are the rollback mechanism for behavior, not for code.

## Consequences

**Positive:**
- Zero dropped requests during deployments: connection draining and traffic shaping ensure
  in-flight requests complete before old pods are terminated.
- Instant rollback for behavior changes without artifact rollback: toggle the feature flag.
- Canary automation catches regressions before they reach 100% of traffic.
- Phased schema migrations decouple data model changes from application version changes.
- Blue/green provides a fast full-rollback path (switch load balancer target) without waiting
  for a new rolling deploy.

**Negative:**
- Running two versions simultaneously during a deployment increases resource usage temporarily.
- Phased schema migrations add latency — a schema change that would take minutes in a big-bang
  migration now spans multiple deployment cycles.
- Feature flag sprawl: old flags that are never cleaned up accumulate technical debt.
  A flag retirement policy is required (flags older than 90 days without a scheduled removal
  date are reviewed quarterly).
- Canary automation requires a reliable set of baseline metrics per service. Services without
  RED metrics and SLOs cannot use automated canary promotion.
- Blue/green requires pre-provisioned infrastructure for the new version while the old version
  is still running, increasing compute cost during transitions.

## Alternatives Considered

### Big-Bang (Recreate) Deployment
Terminate all old pods, then start new pods.

Rejected for production use because: unavoidable downtime during the transition window;
all traffic fails during pod startup; rollback requires another full cycle. Permitted only for
non-production environments where downtime is acceptable.

### In-Place Upgrade (patch running containers)
Modify the running container image without stopping the pod.

Rejected because: this is not a supported Kubernetes operation; it bypasses the pod lifecycle,
probe evaluation, and resource allocation. It is unauditable and non-reproducible.

### Feature Flags as the Only Rollout Mechanism (no traffic shaping)
Deploy 100% of traffic to new code instantly, use feature flags to gate new behavior.

Rejected as the complete strategy because: flags gate behavior, not code. Code bugs (panics,
memory leaks, resource exhaustion) in new code affect all traffic even if the flag is off.
Traffic shaping ensures new code handles only a fraction of requests while its health is
verified.

### Manual Canary (human-driven promotion)
SRE manually monitors the canary and promotes or rolls back based on judgment.

Rejected as the primary mechanism because: human reaction time is too slow for high-traffic
services; humans cannot continuously monitor the canary 24/7; automated promotion with defined
thresholds is more consistent and auditable.