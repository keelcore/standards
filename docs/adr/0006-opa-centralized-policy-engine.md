# ADR-0006: OPA as the Centralized Authorization Policy Engine

**Date:** 2026-03-09
**Status:** Accepted

## Context

Authorization decisions across the platform are currently made in application code, duplicated
per service, and implemented inconsistently. Changing a policy (e.g., adding a new permission
check) requires coordinated changes across multiple services. There is no single place to audit
what policies are in force or to verify that they are consistently applied.

Authorization logic must be:

- Centrally defined and auditable — one place to read and change policy.
- Decoupled from application business logic — services query for decisions, not compute them.
- Versioned and rollback-capable — bad policy changes must be reversible within minutes.
- Testable — policies must have automated tests that run in CI.
- Performant — authorization must not be a latency bottleneck (sub-millisecond for cached inputs).

## Decision

We adopt Open Policy Agent (OPA) as the centralized authorization policy engine.

**Policy language:** Policies are written in Rego. Rego policies are version-controlled in a
dedicated `policies/` repository (or `policies/` subdirectory of the platform repo). Every
policy change requires a pull request with automated Rego unit tests and OPA conformance tests.

**Deployment:** OPA runs as a sidecar alongside each service that requires authorization
decisions, or as a shared cluster-level service for coarse-grained decisions. The sidecar
pattern is preferred for latency-sensitive paths; it eliminates the network hop and allows
in-process caching of decisions.

**Decision interface:** Services call OPA's HTTP API (`POST /v1/data/{policy_path}`) with a
structured input document and receive a structured decision. The service maps the decision to
its access control enforcement. Services do not re-implement policy logic locally.

**Fail-closed:** If OPA is unavailable, authorization decisions fail closed (deny). Services
must handle OPA unavailability as an authorization failure, not as a bypass condition.

**Policy versioning:** Policies are tagged with a version. The currently active policy version
is queryable from OPA's `/v1/policies` endpoint. Rollback to the previous version is a
configuration change that takes effect within 30 seconds.

**Delegation:** Team-level policies (namespace-scoped RBAC) are managed by team leads within
bounds established by platform policy. Platform policy is the ceiling; team policy may be more
restrictive but not more permissive.

## Consequences

**Positive:**

- Single source of truth for all authorization policy — one PR to change behavior everywhere.
- Rego is declarative and testable — policies can be verified in CI before deployment.
- OPA provides a decision log that is ingested by the audit log pipeline — every authorization
  decision is attributable.
- Policy rollback is fast (configuration update, not code deployment).
- OPA is a CNCF graduated project with wide adoption in Kubernetes environments.

**Negative:**

- Rego has a learning curve. Teams accustomed to imperative authorization code must learn a
  new language.
- The sidecar OPA instance is a per-pod infrastructure component. It increases pod startup time
  and resource usage.
- Highly dynamic authorization requirements (e.g., decisions based on real-time external state)
  require OPA to fetch external data via `http.send` or use bundle updates, adding complexity.
- If OPA policy is misconfigured, it can deny legitimate traffic at scale. Policy change
  procedures must include staged rollout and monitoring.

## Alternatives Considered

### Per-Service Authorization Logic

Each service implements its own authorization in application code.

Rejected because: policy is duplicated and diverges; changing platform-wide policy requires
coordinating deployments across every affected service; there is no unified audit log of
authorization decisions; testing is service-scoped, not platform-scoped.

### Casbin (embedded library)

Use the Casbin authorization library embedded in each service.

Rejected because: while Casbin unifies the policy model, policies remain per-service; there
is no centralized policy store; policy changes still require per-service deployments.

### Service Mesh Authorization Policy Only

Use Istio/Linkerd authorization policies for all access control.

Rejected because: service mesh policies are coarse-grained (service-to-service, L4/L7 path).
They cannot express data-level or attribute-level authorization (e.g., "user X can only read
records where tenant_id matches their tenant"). OPA handles both coarse and fine-grained
authorization; mesh policy handles only the coarse layer.

### Cloud IAM (AWS IAM, GCP IAM)

Use the cloud provider's IAM as the authorization engine.

Rejected because: cloud IAM is scoped to cloud resources (S3, GCS, Pub/Sub). It cannot
authorize decisions within the application's own data model. Cloud IAM and OPA serve
complementary scopes; cloud IAM governs infrastructure, OPA governs application resources.
