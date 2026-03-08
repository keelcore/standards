# API Management Standards

These rules govern API design, versioning, rate limiting, quotas, lifecycle management, and
developer experience. They are non-negotiable unless explicitly superseded by a signed ADR.

**Maturity:** Required
**Version:** 1.0.0
**Last Reviewed:** 2026-03-09

## API Design

### Interface Contracts

1. Every API exposes a machine-readable interface definition. REST APIs use OpenAPI 3.1+.
   gRPC services use Protocol Buffers with buf schema registry publication. GraphQL schemas
   are registered in the central schema registry.
2. Interface definitions are version-controlled in the owning service's repository and published
   to the central API catalog on every release.
3. APIs follow a consistent resource-oriented design: nouns for resources, standard HTTP verbs
   (GET, POST, PUT, PATCH, DELETE) for operations, and standard status codes.

### Versioning

4. All APIs are versioned. The version is embedded in the URL path for REST (`/v1/`, `/v2/`).
   gRPC APIs encode the version in the package name (`keelcore.auth.v1`).
5. A version is considered stable once it is deployed to production. Stable versions must not
   receive breaking changes. Add a new version instead.
6. Breaking changes are defined as: removing or renaming a field, changing a field's type,
   removing an endpoint, changing required/optional status of a field, or changing error semantics.
7. Non-breaking additions (new optional fields, new endpoints, new enum values that do not affect
   existing behavior) may be made to a stable version.
8. Deprecated versions remain available for a minimum of 6 months after the successor version
   is available. Deprecation is communicated via the `Deprecation` and `Sunset` response headers
   and in the API catalog.

### Error Responses

9. All error responses use a consistent envelope:

   ```json
   {
     "error": {
       "code": "RESOURCE_NOT_FOUND",
       "message": "The requested resource was not found.",
       "request_id": "<trace_id>",
       "details": []
     }
   }
   ```

10. `code` is a machine-readable uppercase string constant. `message` is human-readable.
    HTTP status codes and `code` values are documented in the API catalog.
11. Error messages must not include internal implementation details (stack traces, SQL queries,
    internal service names) in production responses.

### Pagination

12. All list endpoints that may return more than 100 items support cursor-based pagination.
    Offset pagination is acceptable only for internal tooling APIs.
13. Page size has a maximum (default 100, configurable per endpoint, maximum 1000). Requests
    for unlimited results are rejected.
14. Pagination response includes: `next_cursor`, `prev_cursor` (where supported), `total_count`
    (where computationally feasible), and `has_more`.

## Rate Limiting

### Global Limits

15. All API traffic passes through the centralized rate limiting layer before reaching service pods.
16. Global rate limits protect the platform from aggregate overload. These are set by the platform
    team and documented in the API catalog.
17. Rate limit enforcement uses a token bucket algorithm. Burst capacity may be up to 2× the
    sustained rate for a window of up to 5 seconds.

### Per-Service and Per-Client Limits

18. Every API defines explicit rate limits per endpoint. Rate limits are documented in the API
    catalog alongside the endpoint specification.
19. Rate limits are enforced per API key, per client identity (OAuth client ID), or per
    authenticated user, in that priority order. Unauthenticated traffic shares a shared
    anonymous pool with a lower limit.
20. Services configure rate limits independently of the global limit; the effective limit is
    the minimum of the global and per-service limits.
21. Rate limit state is stored in a shared, distributed backend (e.g., Redis). Per-replica
    in-memory rate limiting that can be bypassed by round-robin routing is prohibited.

### Rate Limit Responses

22. Rate-limited requests receive HTTP 429 with:
    - `Retry-After` header (seconds until the client may retry)
    - `X-RateLimit-Limit` (requests allowed per window)
    - `X-RateLimit-Remaining` (requests remaining in the current window)
    - `X-RateLimit-Reset` (Unix timestamp of window reset)
    - A JSON body following the standard error envelope (rule 9 above)
23. Rate limit headers (`X-RateLimit-*`) are included on every API response, not only on 429s.

### Quotas

24. Usage quotas (distinct from rate limits) enforce longer-window consumption caps (daily,
    monthly) per API key or tenant. Quotas are configured in the API management platform.
25. Quota exhaustion returns HTTP 429 with `code: QUOTA_EXCEEDED` and a `Retry-After` pointing
    to the quota reset time.
26. Quota alerts fire at 80% and 95% consumption to allow clients and operators to take action
    before hard limits are hit.

## Authentication and Authorization

### API Key Management

27. API keys are issued by the central API management platform. Hand-crafted keys are prohibited.
28. API keys are associated with: an owner (human or service), a set of allowed scopes, an
    expiry date, and an environment (keys do not cross environment boundaries).
29. API keys are rotated on a maximum 12-month cycle. Keys that have not been rotated are
    automatically expired and flagged for the owner.
30. API key usage is logged per request with: key ID (never the key value), endpoint, response
    code, and latency.
31. Compromised API keys are revoked within 5 minutes of detection. The platform supports
    emergency bulk revocation for a compromised credential class.

### Scopes and Permissions

32. API scopes are defined at the resource level and follow the pattern `{resource}:{action}`
    (e.g., `orders:read`, `orders:write`). Wildcard scopes are prohibited for non-admin APIs.
33. Clients are issued only the scopes they need. Over-provisioned scopes are flagged in the
    quarterly access review.
34. Admin scopes require MFA-protected issuance and a shorter expiry (maximum 8 hours).

## API Gateway

### Gateway Responsibilities

35. The API gateway handles: routing, authentication verification, rate limiting, WAF enforcement,
    request/response logging, and protocol translation (where needed).
36. Business logic must not reside in gateway configuration. Transformation rules that implement
    business semantics belong in the upstream service.
37. Gateway configuration is version-controlled and deployed via the same GitOps pipeline as
    application code. Manual console edits are prohibited in staging and production.

### Backend Health and Circuit Breaking

38. The gateway enforces circuit breakers for each upstream service. A service that exceeds the
    error threshold (5xx rate > 50% for 10 seconds) is circuit-broken; traffic is rejected at
    the gateway with HTTP 503 until the upstream recovers.
39. Upstream health checks are configured per route. The gateway does not route to unhealthy
    upstreams.

### Observability at the Gateway

40. The gateway emits per-endpoint metrics: request rate, error rate, latency (p50/p95/p99),
    and upstream latency. These are automatically included in each API's RED dashboard.
41. Every request is tagged with a `request_id` injected or verified by the gateway. The
    `request_id` matches the `trace_id` in distributed traces.

## API Lifecycle

### Catalog and Discovery

42. Every API is registered in the central API catalog before its first production deployment.
    Unregistered APIs are blocked by admission control.
43. The catalog entry includes: service owner, SLO, rate limits, authentication requirements,
    versioning status, deprecation dates (if applicable), and a link to the OpenAPI/Protobuf spec.
44. The catalog is queryable by all engineers and is the single source of truth for API
    discoverability.

### Deprecation and Retirement

45. API retirement follows a defined process: announce deprecation (Sunset header + catalog
    update), monitor usage, notify active consumers, enforce sunset date.
46. An API version with active traffic cannot be retired without consumer migration or an
    explicitly accepted exception.
47. The `Sunset` date is set in UTC and announced at least 6 months in advance for externally
    consumed APIs, 30 days for internal-only APIs.

## Do Not

- Publish an API without an OpenAPI/Protobuf spec in the central catalog.
- Make breaking changes to a stable API version.
- Issue API keys outside the central API management platform.
- Cross environment boundaries with API keys.
- Return internal stack traces or SQL errors in production API responses.
- Implement rate limiting as per-replica in-memory state.
- Configure the gateway with business logic or inline transformations.
- Retire an API version with active consumers without an approved migration plan.
- Return list endpoints without pagination for collections that may grow beyond 100 items.
- Omit rate limit headers from API responses.
