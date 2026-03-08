# ADR-0008: Rapid Key Rotation with a 5-Minute Platform SLA

**Date:** 2026-03-09
**Status:** Accepted

## Context

When a cryptographic key or secret is compromised, the window between detection and full
rotation across the network determines the attacker's dwell time. Long rotation windows —
hours or days — are unacceptable for high-value keys (mTLS root CAs, data encryption keys,
JWT signing keys).

Manual rotation procedures are too slow and error-prone under incident conditions. Services
that require a restart to pick up new keys extend the rotation window and cause downtime.

Requirements for key rotation:

- Platform-wide propagation must complete in 5 minutes or less.
- Services must not require a restart to reload keys.
- Rotation must be triggered programmatically (automated schedule and emergency manual trigger).
- Every rotation event must produce an immutable audit log entry.
- The solution must work for mTLS certificates (SPIFFE SVIDs), data-at-rest encryption keys,
  and application secrets (API keys, JWT signing keys).

## Decision

We establish a Formal Rapid Key Rotation (FRKR) standard with a 5-minute platform SLA for
the entire network.

**Signal-based reload:**
Services reload key material upon receiving a designated signal (`SIGUSR1` on Linux workloads)
or a push notification from the key management system (KMS webhook or watch API). Services must
not poll for key changes on a long interval; push-based notification is required.

**Key material sources:**

- SPIFFE SVIDs: rotated by SPIRE automatically; services reload via the Workload API watch stream.
  SPIRE is configured with a maximum SVID TTL of 24 hours and a rotation buffer of 50% of TTL.
- Data-at-rest encryption keys: rotated by the KMS (HashiCorp Vault or cloud-native KMS).
  Applications use the KMS envelope encryption pattern — they hold a data encryption key (DEK)
  wrapped by a key encryption key (KEK). On rotation, only the KEK rotates; the KMS re-wraps
  the DEK automatically. The application reloads the re-wrapped DEK on signal.
- JWT signing keys: rotated by the token issuance service. New keys are published to the JWKS
  endpoint before the old key is retired. Verifying services poll the JWKS endpoint on a
  30-second interval or on signal.

**Emergency rotation:**
A `rotate-keys emergency` command in the platform CLI triggers full rotation across all key
classes. The command sends the reload signal to all affected pods via the orchestrator's exec
or signal API, then polls health endpoints to verify all pods have reloaded. The command exits
non-zero if any pod fails to acknowledge rotation within the 5-minute SLA.

**Audit logging:**
Every rotation event (scheduled or emergency) emits an audit log entry with: key ID, key class,
rotation trigger (`scheduled` or `emergency`), actor, start time, and completion time.

**Quarterly rotation drill:**
Emergency rotation is exercised in the staging environment at least once per quarter. Results
(actual rotation time, any pod failures) are documented. Rotation time exceeding 3 minutes in
staging triggers a remediation review.

## Consequences

**Positive:**

- A compromised key is rotated across the entire platform within 5 minutes, minimizing
  attacker dwell time after detection.
- Signal-based reload means rotation is zero-downtime — no pod restarts are required.
- The KMS envelope encryption pattern means re-encrypting bulk data is not required on KEK
  rotation — only the wrapped DEK is updated.
- Automated quarterly drills verify the rotation path is functional before an emergency occurs.
- Audit logs provide a complete rotation history for compliance and post-incident review.

**Negative:**

- Signal-based reload requires that applications implement a signal handler that atomically
  replaces key material in memory. This is a non-trivial implementation requirement that must
  be enforced via SDK-level support.
- The 5-minute SLA is aggressive for large clusters. At high replica counts, sending the reload
  signal to all pods and verifying acknowledgment within 5 minutes requires parallel execution
  and careful timeout management.
- JWKS polling at 30-second intervals means there is up to a 30-second window where a verifier
  is using a key that has been retired. The old key must remain in the JWKS endpoint for at
  least 60 seconds after rotation.
- Emergency rotation of data-at-rest encryption keys (KEK) requires that all encrypted data
  stores are accessible to the KMS for re-wrapping. Stores that are offline during rotation
  must be addressed before coming back online.

## Alternatives Considered

### Periodic Scheduled Rotation Only (No Emergency Path)

Rotate keys on a fixed schedule (e.g., every 24 hours) via a cron job.

Rejected because: scheduled rotation does not address the emergency case where a key is
known or suspected to be compromised. The attacker's dwell time is bounded only by the
rotation schedule, not by detection time.

### Restart-Based Reload

Trigger a rolling restart of all pods to pick up new key material from the environment
or mounted secret.

Rejected because: rolling restarts take minutes to hours for large deployments; they consume
CPU and memory burst capacity; they trigger readiness probe failures and briefly reduce
serving capacity. A restart-based approach cannot meet the 5-minute SLA at scale.

### Long-Lived Keys with Revocation Lists

Issue long-lived keys and maintain a Certificate Revocation List (CRL) or OCSP responder.

Rejected because: CRL propagation delay can be hours or days; OCSP adds a synchronous
network call to every authentication; revocation list maintenance is operationally complex.
Short-lived keys with rapid rotation are strictly better than long-lived keys with revocation.

### Manual Rotation Procedure

Document a runbook and rely on human execution during incidents.

Rejected because: human execution under incident pressure introduces errors; coordination
across a large pod fleet is too slow; manual steps cannot reliably meet a 5-minute SLA.
