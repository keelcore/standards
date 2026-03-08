# ADR-0004: SPIFFE/SPIRE for Workload Identity

**Date:** 2026-03-09
**Status:** Accepted

## Context

Services need to authenticate to each other and to external systems. Common approaches include
shared secrets, static API keys, and per-service certificates managed manually. These approaches
create credential sprawl, make rotation difficult, and produce credentials that outlive the
workloads they were issued for.

The platform runs on Kubernetes with a service mesh. The identity system must be:

- Cryptographically verifiable (not based on claimed headers or IP address).
- Automatic — no human issues or rotates credentials for individual service instances.
- Short-lived — credential lifetime is bounded by the workload lifetime, not a renewal schedule.
- Auditable — every issuance and revocation is logged.

## Decision

We adopt SPIFFE (Secure Production Identity Framework for Everyone) as the identity standard
and SPIRE (SPIFFE Runtime Environment) as the implementation.

Every workload receives a SPIFFE Verifiable Identity Document (SVID) — an X.509 certificate
or JWT — issued by the SPIRE server. SVIDs encode the workload's identity as a SPIFFE ID:
`spiffe://trust-domain/service-name/instance`.

SVID issuance is automatic via the SPIRE agent running on each node. SVIDs have a maximum
24-hour TTL and are rotated automatically before expiry, with zero service restart required.
The service mesh (Istio or Linkerd) consumes SVIDs to establish mTLS for all east-west traffic,
enforcing the service mesh authorization policy.

JWT SVIDs are issued for workloads that need to authenticate to external services that do not
support mTLS (e.g., external APIs, cloud provider control planes). JWT SVIDs use RS256 and
include a short `exp` claim (maximum 15 minutes).

## Consequences

**Positive:**

- No shared secrets or static API keys for service-to-service auth — credential sprawl eliminated.
- Automatic rotation with 24-hour maximum lifetime limits blast radius of a compromised SVID.
- SPIFFE IDs are platform-agnostic; workloads can move between Kubernetes clusters and on-prem
  without changing their identity model.
- SPIRE integrates directly with Kubernetes attestation (pod SA token, node attestation) —
  no additional sidecar process needed beyond the SPIRE agent daemonset.
- SPIFFE is a CNCF graduated project with wide industry adoption and active maintenance.

**Negative:**

- SPIRE server is a critical infrastructure component; its unavailability prevents new
  workload identity issuance. High-availability SPIRE server deployment is required.
- Teams unfamiliar with PKI concepts will need training to understand SVIDs and trust bundles.
- External services that do not support mTLS require additional integration (JWT SVID exchange
  or SPIFFE federation).
- Trust bundle rotation (root CA) is a platform-level operation that requires coordination
  across all clusters.

## Alternatives Considered

### Kubernetes Service Account Tokens with Projected Volumes

Kubernetes issues OIDC-backed JWT tokens to pods via projected volumes. Tokens are short-lived
(default 1 hour) and bound to the pod's service account.

Rejected because: token audience is Kubernetes-specific; using the token for service-to-service
auth requires every verifying service to call the Kubernetes API. This couples services to the
cluster's Kubernetes API server and does not support multi-cluster or off-cluster workloads
without additional complexity.

### HashiCorp Vault AppRole / Kubernetes Auth

Vault issues secrets to pods that authenticate via Kubernetes service account tokens.

Rejected as the primary identity mechanism because: it adds Vault as a dependency on the
authentication critical path. Vault is retained as the approved secrets manager (for secret
values, not for identity), but identity must not depend on a separate secret-injection flow
per workload.

### Static mTLS Certificates per Service

A PKI team issues long-lived certificates per service, distributed via Kubernetes secrets.

Rejected because: manual issuance and rotation does not scale; long-lived certificates
(months to years) dramatically increase blast radius of compromise; no automated revocation
path for compromised instances.

### Network-Level Identity (IP-based)

Trust the source IP address to determine caller identity.

Rejected immediately. IP addresses are not cryptographically bound to an identity; NAT and
load balancers make them unreliable; IP-based trust is trivially spoofable within the cluster.
