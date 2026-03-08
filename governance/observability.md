# Observability Standards

These rules govern metrics, logging, tracing, and alerting across all services. They are non-negotiable.

## Metrics

### Vendors and Retention

1. The approved metrics vendor(s) are documented in the internal vendor registry. No additional metrics
   backends are introduced without ARB approval.
2. Metrics retention: real-time resolution (≤60s) for 15 days; 5-minute rollup for 90 days;
   1-hour rollup for 13 months.
3. Long-term retention beyond 13 months requires explicit data classification and archival approval.

### Taxonomy and Namespace Schema

4. All metric names follow the schema: `{org}_{service}_{noun}_{unit}` (e.g., `keelcore_auth_requests_total`).
5. Metric namespaces are registered centrally; unregistered namespaces are rejected at the ingestion layer.
6. Label keys are lowercase snake_case. Label values must not contain high-cardinality free-text (e.g.,
   user IDs, trace IDs, URLs). Cardinality limit per metric: 10,000 distinct label value combinations.

### Required Metric Ontologies

7. Every service exposes RED metrics: **R**ate (requests per second), **E**rrors (error rate),
   **D**uration (latency distribution — p50, p95, p99).
8. Every resource-bound component (database, cache, message queue, worker pool) exposes USE metrics:
   **U**tilization, **S**aturation, **E**rrors.
9. RED and USE dashboards are provisioned automatically from the service's metric registration.

### SLOs and SLAs

10. Every public-facing service defines at least one SLO expressed as an error budget (e.g., 99.9%
    availability over a 30-day rolling window).
11. SLO burn-rate alerts fire at 2× and 10× burn rates and are routed to the on-call rotation.
12. SLAs, where contractually defined, are backed by SLOs with sufficient headroom. SLA breach
    thresholds are stricter than internal SLO thresholds.
13. Service dashboards are published to the central dashboard registry and linked from the service runbook.

## Logging

### Format

14. All log output is structured JSON. Human-readable plain text logs are prohibited in staging and
    production. Development environments may use formatted output via a local flag.
15. Log lines are single-line JSON objects terminated by `\n`. Multi-line log entries are prohibited;
    stack traces are serialized into a single string field.

### Required Fields

16. Every log entry must include:
    - `timestamp` — RFC 3339 with nanosecond precision (e.g., `2026-03-09T12:00:00.000000000Z`)
    - `level` — one of: `debug`, `info`, `warn`, `error`, `fatal`
    - `service` — the service identifier (matches the metric namespace prefix)
    - `version` — the deployed artifact version (SemVer)
    - `trace_id` — W3C TraceContext trace ID (zero value if no active trace)
    - `span_id` — W3C TraceContext span ID (zero value if no active trace)
    - `message` — human-readable description of the event
17. Additional fields are encouraged but must not collide with the reserved field list above.

### SDK-Level Enforcement

18. Services must use the organization-approved logging SDK. Calls to raw `fmt.Println`,
    `console.log`, `print()`, or equivalent bypass the structured logger and are prohibited.
19. The logging SDK enforces required fields at construction time. A log entry missing a required
    field must fail at build time or panic at startup, not silently emit a malformed log.

### Aggregation and Retention

20. All logs from all environments (staging, production) are shipped to the central log aggregation
    platform. Local-only logging is prohibited in staging and production.
21. Log retention: 90 days at full fidelity; 13 months for `warn` and above; 7 years for `audit`
    classified logs.
22. Log access is role-gated. Read access to production logs requires an approved role. Queries
    on `audit`-classified logs are themselves logged.

### Redaction and Privacy

23. Personally identifiable information (PII) must not appear in log fields except `audit`-classified
    logs with explicit data handling approval.
24. Secrets, tokens, passwords, and private keys must never be logged, even at `debug` level.
25. The logging SDK must provide a redaction hook that masks known-sensitive field patterns before
    emission. Services must register PII-bearing fields with the redaction registry.
26. Audit logs that require PII (e.g., access logs for compliance) are stored in a segregated
    audit log store with stricter access controls and encryption-at-rest.

## Distributed Tracing

### Framework

27. All services instrument using OpenTelemetry (OTel). Vendor-specific tracing SDKs are prohibited
    as the primary instrumentation layer. OTel exporters may target any approved backend.
28. Trace context is propagated using the W3C TraceContext standard (`traceparent`, `tracestate` headers).
    Proprietary propagation formats (B3, X-Cloud-Trace-Context) are acceptable as secondary propagation
    only for legacy integration.

### Propagation Policy

29. Every inbound request must extract trace context from headers if present, or generate a new root
    span if absent.
30. Every outbound call must inject the current trace context into request headers.
31. Internal background jobs and queue consumers must attach to the trace context embedded in the
    job/message payload.
32. Trace context must cross service, database, queue, and cache boundaries. Traces that terminate
    at a service boundary rather than propagating downstream are a defect.

### Sampling

33. Production sampling: head-based sampling at 1% for high-volume steady-state traffic, with tail-based
    sampling capturing 100% of error traces and traces exceeding the p99 latency threshold.
34. Sampling configuration is centralized (not per-service). Services do not configure their own sampling
    rates without approval.
35. Staging and development environments use 100% sampling.

## Audit Logging

### Immutability and Trail Requirements

36. Sensitive actions (authentication events, authorization decisions, configuration changes, data
    exports, administrative actions) must emit an `audit`-classified log entry.
37. Audit logs are written to an append-only, tamper-evident store. Application processes have write-only
    access; no application process may read, modify, or delete audit log entries.
38. Every audit log entry includes: `timestamp`, `actor_id`, `actor_type` (human or service),
    `action`, `resource_type`, `resource_id`, `outcome` (success or failure), `client_ip`, `trace_id`.
39. Access to resources and modifications to data are logged, including read access to sensitive data.

### Retention

40. Audit logs are retained for a minimum of 7 years unless a longer period is required by applicable
    regulation.
41. Audit log exports for compliance review require dual-approval and are themselves logged.

## Alerting

### Thresholds and Routing

42. Every SLO has an associated burn-rate alert. Alerts fire at 2× burn (page candidate) and 10× burn
    (immediate page).
43. `error` and `fatal` log events that exceed a per-service threshold trigger an alert.
44. Alert routing follows the on-call schedule managed in the central incident management platform.
45. Alerts include: service name, environment, metric/log source, threshold breached, current value,
    link to the relevant dashboard, and link to the runbook.
46. Runbook links in alerts must resolve. Broken runbook links are treated as a P2 incident.

## Do Not

- Emit plain-text or unstructured logs in staging or production.
- Log PII outside of approved audit log stores.
- Log secrets, tokens, or credentials at any log level.
- Define per-service sampling rates without central approval.
- Omit required log fields.
- Use vendor-specific tracing SDKs as the primary instrumentation layer.
- Allow traces to terminate at a service boundary rather than propagating downstream.
- Deploy a service without RED metrics, SLO definition, and a linked dashboard.
- Ship alerts without runbook links.
