# Platform Architecture Standards

These rules govern platform-level decisions across networking, DNS, TLS, WAF, and traffic management.
They are non-negotiable unless explicitly superseded by a signed ADR.

## Governance Process

### Decision-Making (DACI)
1. All platform architecture decisions use DACI: one Driver, one Approver (Architecture Review Board
   chair or delegate), Consulted stakeholders, and Informed parties.
2. The Driver authors the RFC and owns shepherding it through review.
3. The Approver has final authority; no decision is binding without Approver sign-off.
4. Decisions that affect more than one service domain require ARB review before implementation.

### RFC Process
5. Any change to platform standards, vendor selection, or network topology requires an RFC.
6. RFC template: problem statement, proposed solution, alternatives considered, rollout plan, rollback plan.
7. RFC comment period is a minimum of five business days for standard changes; urgent security patches
   may compress to 24 hours with ARB chair notification.
8. Accepted RFCs are archived in `docs/rfc/` with status and the date of acceptance.

### Architecture Review Board (ARB)
9. ARB meets on a defined cadence (minimum monthly); decisions and attendance are published to the
   engineering wiki within five business days of each meeting.
10. ARB publishes a versioned Architecture Standards document at least once per quarter.
11. Previous versions of Architecture Standards are archived and permanently accessible.

## Domain and IP

### Domain Registrar
12. All domains are registered through the approved corporate registrar (documented in the internal
    vendor registry). Personal or team-owned registrar accounts are prohibited for production domains.
13. Domain transfers require ARB approval and a change record.
14. WHOIS privacy protection is enabled on all externally registered domains.

### IP Address Management
15. IP allocations are managed through the approved IPAM vendor (documented in the internal vendor registry).
16. All IP blocks are tagged with owner, environment, and region.
17. IPv4 and IPv6 are both required for all new public-facing services. Dual-stack is the baseline; IPv4-only
    services are not accepted for new deployments.
18. Private RFC 1918 ranges are used for internal pod and node networks. Overlap with VPN or on-premises
    ranges must be approved through the IPAM change process.

## DNS

### Zone Management
19. DNS zones are managed through the approved DNS vendor (documented in the internal vendor registry).
    Manual zone edits via vendor UI are prohibited except in a documented break-glass scenario.
20. All zone changes are driven from infrastructure-as-code (Terraform, Pulumi, or equivalent) in a
    version-controlled repository. Zone state is reconciled on every deployment.
21. Internal and external zones are segregated. Internal zone resolvers are not exposed to the public internet.

### Required Record Types
22. Public services must expose: A, AAAA, and the appropriate CNAME or alias records.
23. Email domains must have SPF, DKIM, and DMARC records. DMARC policy must be `p=quarantine` or stricter
    in production.
24. Wildcard DNS records (`*.example.com`) are permitted only for edge/ingress controllers that validate
    per-host routing internally. Wildcard records must not resolve to application pods directly.
25. Internal service discovery uses a dedicated internal TLD (e.g., `.internal` or cluster DNS suffix).
    Internal records are never propagated to public resolvers.

## TLS and Certificate Management

### Certificate Issuance
26. TLS certificates for public endpoints are issued from an approved CA vendor (documented in the internal
    vendor registry). Self-signed certificates are prohibited on any public-facing endpoint.
27. Certificate issuance and renewal must use the ACME protocol. Manual certificate downloads and uploads
    are prohibited except in a documented break-glass scenario.
28. Certificates are provisioned and renewed automatically. Expiry-based alerts fire at 30 days and again
    at 7 days before expiration.

### Mutual TLS (mTLS)
29. East-west traffic between services must use mTLS. Plaintext service-to-service communication is
    prohibited in staging and production.
30. mTLS certificates are issued by the internal PKI (SPIFFE/SPIRE or equivalent). Leaf certificates
    rotate on a maximum 24-hour lifetime. Rotation is automatic and zero-downtime.
31. mTLS policy is enforced at the service mesh layer, not individually per application.

### Supported Protocols and Cipher Suites
32. Minimum TLS version: TLS 1.2. TLS 1.3 is required for all new integrations.
33. TLS 1.0 and TLS 1.1 are prohibited on all endpoints.
34. Cipher suites: prefer ECDHE key exchange with AES-GCM or ChaCha20-Poly1305. RC4, DES, 3DES,
    and export-grade ciphers are prohibited. DHE suites below 2048-bit DH parameters are prohibited.
35. HSTS is required on all HTTPS endpoints with `max-age` of at least one year.

## Web Application Firewall (WAF) and DDoS

### WAF
36. All public HTTP/HTTPS ingress passes through the WAF layer before reaching application pods.
37. The OWASP Core Rule Set (CRS) is enforced in blocking mode. Detection-only mode is not
    acceptable for production. Tuning exceptions require a documented rule with justification.
38. WAF rules are version-controlled. Rule changes follow the RFC process.
39. WAF logs are ingested into the central log aggregation platform with a minimum 90-day retention.

### DDoS Protection
40. All public endpoints are protected by volumetric DDoS mitigation at the network edge.
41. L7 DDoS (HTTP flood) mitigation is enforced by the WAF layer with rate limiting rules.
42. Incident response runbooks for DDoS events are maintained and reviewed quarterly.

## Security Headers
43. All HTTP responses from public endpoints must include:
    - `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
    - `X-Content-Type-Options: nosniff`
    - `X-Frame-Options: DENY`
    - `Content-Security-Policy` (service-specific, reviewed by security team)
    - `Referrer-Policy: strict-origin-when-cross-origin`
    - `Permissions-Policy` (restrictive default; expand per-service with justification)
44. `Server` and `X-Powered-By` response headers must be suppressed or overridden to not reveal
    implementation details.

## Traffic Management

### Payload Limits
45. Default maximum upload size: 10 MB. Services requiring larger uploads must document and configure
    an explicit limit; unbounded uploads are prohibited.
46. Maximum request body size: 1 MB by default for API endpoints. Streaming endpoints must implement
    backpressure.
47. Maximum response size is bounded by the service contract. Unbounded response streaming must
    implement flow control.

### Rate Limiting
48. Global rate limiting is enforced at the edge/ingress layer.
49. Per-service rate limits are configured and documented in each service's runbook.
50. Rate limit responses use HTTP 429 with a `Retry-After` header.
51. Rate limit state is shared across edge replicas (e.g., Redis-backed or edge-native distributed
    counters). Per-replica rate limiting that allows bypass via replica selection is prohibited.

### Session Management
52. Session tokens are cryptographically random with a minimum of 128 bits of entropy.
53. Session lifetime: configurable per service, with a maximum idle timeout of 15 minutes and a
    maximum absolute session lifetime of 8 hours for human-facing sessions.
54. Sessions are invalidated server-side on logout. Client-side deletion alone is insufficient.
55. Session refresh tokens must be rotated on every use.

## Do Not
- Register production domains outside the approved registrar.
- Assign IP blocks without IPAM tracking.
- Modify DNS zones outside of infrastructure-as-code.
- Deploy new services without IPv6 support.
- Use TLS 1.1 or below on any endpoint.
- Issue certificates manually when ACME automation is available.
- Allow service-to-service plaintext in staging or production.
- Run OWASP WAF rules in detection-only mode in production.
- Deploy public endpoints without DDoS protection.
- Omit required security headers.
- Accept unbounded file uploads without an explicit, documented size cap.