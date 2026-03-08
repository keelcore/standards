# ADR-0005: OpenTelemetry as the Unified Observability Framework

**Date:** 2026-03-09
**Status:** Accepted

## Context

The platform runs many services in multiple languages (Go, Node, Python). Each service needs
metrics, logs, and traces. Without a unified framework, each team chooses its own SDK and
backend, producing fragmented observability: trace IDs do not propagate across language
boundaries, dashboards are inconsistent, and switching backends requires touching every service.

The observability framework must:

- Work across all supported languages without per-language reimplementation of propagation logic.
- Decouple instrumentation from the backend — changing from one metrics or tracing vendor to
  another must not require changes to application code.
- Support W3C TraceContext propagation natively so trace IDs cross service, queue, and database
  boundaries.
- Be governed by a stable, vendor-neutral specification that reduces lock-in risk.

## Decision

We adopt OpenTelemetry (OTel) as the single observability instrumentation framework across all
services and languages.

**Instrumentation:** Services use the language-specific OTel SDK for metrics, traces, and logs.
Vendor-specific SDKs are prohibited as the primary instrumentation layer.

**Propagation:** W3C TraceContext (`traceparent`, `tracestate`) is the required propagation
format for all HTTP, gRPC, and message queue integrations. B3 and X-Cloud-Trace-Context headers
are supported as read-only fallback for legacy upstream callers but are not propagated outbound.

**Export:** The OTel Collector runs as a DaemonSet. Services export to the local Collector via
OTLP gRPC (localhost). The Collector handles batching, retry, and backend-specific export.
Backend selection (Prometheus, Jaeger, Grafana Tempo, Datadog, etc.) is an operational decision
managed in the Collector config, not in application code.

**Metrics ontology:** RED (Rate, Error, Duration) is required for every request-serving component.
USE (Utilization, Saturation, Errors) is required for every resource component. These are
instrumented at the SDK level; dashboards are auto-generated from metric registration.

**Sampling:** Head-based sampling at 1% for high-volume steady-state, with tail-based sampling
capturing 100% of error traces and traces exceeding the p99 latency SLO threshold. Sampling
configuration lives in the Collector, not in individual services.

## Consequences

**Positive:**

- Instrumentation code is portable: switching backends requires only Collector reconfiguration,
  not application changes.
- W3C TraceContext propagates traces across all languages and across external services that
  also adopt W3C TraceContext (growing ecosystem).
- OTel is a CNCF graduated project with broad language SDK coverage and active vendor support.
- The OTel Collector provides buffering and retry — services are decoupled from backend
  availability and do not lose data during backend maintenance windows.
- Centralized sampling at the Collector allows dynamic adjustment without deploying application
  code changes.

**Negative:**

- OTel SDKs are still evolving; API stability varies by language and signal (logs API is less
  mature than traces). Teams may encounter breaking SDK changes across minor versions.
- The OTel Collector DaemonSet is a required infrastructure component; its failure degrades
  observability. HA deployment and monitoring of the Collector itself is required.
- Auto-instrumentation (agent-based) may not capture all spans, particularly for proprietary
  or unusual frameworks. Manual instrumentation is required for gaps.
- Engineers must learn OTel concepts (Tracer, Span, Context propagation, Resource attributes)
  rather than using simpler vendor-specific libraries.

## Alternatives Considered

### Per-Language Vendor SDK (Datadog, New Relic, Honeycomb)

Each team uses the vendor's native SDK for their language.

Rejected because: traces do not propagate across language boundaries without vendor-specific
propagation headers; switching vendors requires touching every service; vendor SDKs encode
backend choice in application code.

### Prometheus client + Jaeger client (no OTel)

Use Prometheus client libraries for metrics and the Jaeger client for tracing directly.

Rejected because: two separate SDKs do not share context propagation; logs remain a third
unconnected stream. OTel provides a unified context model across all three signals. Prometheus
and Jaeger are viable backends but the instrumentation layer should be OTel.

### No framework (structured logging only)

All observability via structured logs; derive metrics and traces from log parsing.

Rejected because: log-derived metrics have high cardinality cost and latency; trace reconstruction
from logs is imprecise; this approach does not scale to high-throughput services.
