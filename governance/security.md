# Security Standards

These rules govern identity and access management, encryption, key management, and data handling.
They are non-negotiable unless explicitly superseded by a signed ADR.

**Maturity:** Required
**Version:** 1.0.0
**Last Reviewed:** 2026-03-09

## Identity and Access Management

### Federated Authentication

1. All human-facing authentication uses a federated identity provider (IdP) via OIDC or SAML 2.0.
   Local username/password stores are prohibited for production systems.
2. The approved AuthN vendor(s) are documented in the internal vendor registry. No additional identity
   providers are introduced without ARB approval and a security review.
3. Multi-factor authentication (MFA) is required for all human accounts. Phishing-resistant MFA
   (FIDO2/WebAuthn) is required for privileged and production access.

### Workload Identity

4. Service-to-service authentication uses SPIFFE/SPIRE (or an equivalent SVID-based workload identity
   system). Static shared secrets for service identity are prohibited.
5. SPIFFE Verifiable Identity Documents (SVIDs) are issued with a maximum 24-hour TTL and rotated
   automatically.
6. JWT-based identity is acceptable for external API integrations where SPIFFE is not available.
   JWTs must be signed (RS256 or ES256 minimum) and have an explicit `exp` claim. Unsigned or
   HS256-signed JWTs are prohibited in production.

### Token Lifecycle and Revocation

7. Access tokens have a maximum lifetime of 15 minutes. Refresh tokens have a maximum lifetime of
   8 hours for human sessions; service refresh tokens do not exist (workload identity handles renewal).
8. Token revocation is effective within 60 seconds. Caches that hold token validation results must
   honor the revocation TTL.
9. Refresh tokens are single-use and rotated on every use. Reuse of a refresh token triggers
   immediate session termination and a security alert.
10. All issued tokens are logged with: issuer, subject, audience, `jti`, issued-at, and expiry.

## Authorization

### Service-Level Routing AuthZ

11. API gateways and ingress controllers enforce coarse-grained authorization (service-to-service
    trust boundaries) before traffic reaches application pods.
12. Services must not trust the caller's claimed identity from request headers alone; the identity
    assertion must be cryptographically verified (mTLS client cert or verified JWT) by the mesh or
    gateway layer.

### Role-Based Access Control (RBAC)

13. RBAC roles are defined at the minimum privilege required for each function. There are no
    "superuser" roles in production except for documented break-glass accounts.
14. Role assignments are reviewed quarterly. Stale role assignments are revoked automatically after
    90 days without reaffirmation.
15. Role definitions and assignments are stored in version-controlled configuration. Manual UI-based
    role grants that bypass version control are prohibited.

### Attribute-Based Access Control (ABAC)

16. Fine-grained access decisions (data-level, row-level) are implemented via ABAC policies in the
    centralized policy engine (OPA or equivalent).
17. ABAC policies are co-located with the service that owns the resource. Cross-service policy
    definitions require ARB approval.

### Centralized Policy Engine

18. The approved policy engine (OPA or equivalent) is the single source of truth for all
    authorization decisions. Services must not implement ad-hoc authorization logic that duplicates
    or overrides centralized policy.
19. Policies are version-controlled. Every policy change requires a review and an audit log entry.
20. The policy engine exposes a health endpoint; its unavailability must cause authorization
    decisions to fail closed (deny), not fail open (permit).

### Policy Versioning and Rollback

21. Policies are tagged with a version identifier. The current version in force is queryable from
    the policy engine.
22. Any policy change can be rolled back to the previous version within 5 minutes via the policy
    engine's rollback mechanism.

### Delegated Permissions

23. Delegated admin domains (e.g., team-level RBAC management) are scoped to the team's namespace.
    Cross-namespace privilege delegation requires ARB approval.
24. OAuth 2.0 delegated scopes must be explicitly documented per API. Broad wildcard scopes
    (e.g., `*`, `admin`) are prohibited unless the API is itself an admin API.

## Encryption

### Encryption in Transit

25. All traffic between pods, nodes, and external systems is encrypted. Plaintext communication
    inside the cluster is prohibited in staging and production.
26. Service-to-service encryption is enforced via mTLS at the service mesh layer.
27. Traffic to external APIs uses TLS 1.2 minimum; TLS 1.3 preferred. See `governance/platform.md`
    for cipher suite requirements.

### Encryption at Rest

28. All persistent data stores (databases, object storage, message queues, caches) encrypt data
    at rest using AES-256 or equivalent.
29. Encryption keys for data at rest are managed by the approved key management service (KMS)
    and never stored alongside the data they protect.
30. Backup and snapshot data is encrypted with the same or stronger controls as primary data.

### Key Management

31. The approved KMS vendor(s) are documented in the internal vendor registry. Application-managed
    key stores (manual key files, hardcoded keys) are prohibited.
32. Encryption keys are rotated on a defined schedule: symmetric keys every 90 days, asymmetric
    keys every 12 months, unless a shorter rotation is required by compliance or incident response.
33. Key rotation is zero-downtime. Services must reload keys without restart.

### Formal Rapid Key Rotation

34. The platform must support emergency key rotation with an SLA of 5 minutes or less for the
    entire network.
35. Services must reload encryption keys upon receiving a designated OS signal (e.g., SIGUSR1)
    or a KMS-pushed notification, without process restart.
36. Key rotation events are logged in the audit log with: key ID, rotation trigger (scheduled or
    emergency), actor, and timestamp.
37. Emergency key rotation is tested in staging at least quarterly. Results are documented.

## Data Classification and Handling

38. All data is classified at creation time as one of: `public`, `internal`, `confidential`,
    or `restricted`. Classification is stored as metadata alongside the data.
39. `confidential` and `restricted` data must be encrypted at rest and in transit, accessed only
    via authorized roles, and logged on every access.
40. `restricted` data (e.g., payment card data, health records) must also be isolated in dedicated
    storage with network-level segmentation from general-purpose stores.
41. Data handling procedures for each classification level are documented in the internal data
    handling policy. That policy is reviewed annually and after any significant breach or
    compliance change.

## Do Not

- Use local username/password stores for production authentication.
- Use shared static secrets for service-to-service authentication.
- Issue unsigned or HS256-signed JWTs in production.
- Allow authorization to fail open when the policy engine is unavailable.
- Make ad-hoc role grants that bypass version-controlled configuration.
- Store encryption keys alongside the data they protect.
- Hardcode encryption keys or tokens in application code or config files.
- Perform key rotation that requires a service restart.
- Log, print, or expose key material at any log level.
- Allow `restricted` data in general-purpose storage.
