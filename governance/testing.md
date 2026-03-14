# Testing Standards

These rules govern all test code and test infrastructure in this project. They are non-negotiable.

**Maturity:** Required
**Version:** 1.0.0
**Last Reviewed:** 2026-03-14

## Core Principle

Unit tests do not cross system boundaries.

A system boundary is anything that requires a network peer, an OS service, or an external process.
If a test needs one of those, it is an integration test and belongs in BATS, Compose, or a
cluster-level suite — not in a `_test.go` file.

## What Goes in Unit Tests

- Config parsing and validation (all fields, all error branches)
- Data transformations and serialization
- State machine transitions (circuit breaker, reload lifecycle)
- Middleware wiring and handler composition
- Error branches on bad or missing inputs
- Pure logic with no I/O

## What Goes in Integration Tests

- ACME end-to-end certificate issuance — use a real ACME test CA (e.g. pebble)
- OPA policy evaluation — use a real OPA process
- Remote logging sink reachability — real HTTP or syslog endpoint
- Upstream proxy behavior — real HTTP upstream server
- Syslog emission — real syslog daemon
- Compose and Kubernetes deployment smoke tests

## Real Tools Over Mocks

Do not mock external systems. Use real implementations in integration tests.

Mocks replicate the mock author's understanding of a contract at a point in time. When the real
system changes, mocks silently pass. Real tools catch contract drift.

Acceptable alternatives to real systems:

- In-process test servers (e.g. `httptest.NewServer`) for HTTP — acceptable in unit tests.
- Real test daemons (pebble, OPA, syslog) — required in integration tests.
- Never: mocked network peers, mocked OS services, mocked external processes.

## Test Suite Structure

Every project MUST define the following test layers. Names and Makefile targets are fixed.

| Layer | Makefile target | Scope | External deps |
|---|---|---|---|
| Unit | `make unit-test` | In-process logic; no system boundaries | None |
| Integration | `make integration-test` | Binary + real peers | Test daemons on PATH |
| Compose | `make test-compose` | Full stack via Docker Compose | Docker |
| Kubernetes | `make test-k8s` | Helm deploy + pod probes | kind / Docker |

## Test File Layout

- Unit tests: `_test.go` files co-located with the package under test.
- BATS integrity: `tests/integrity.bats` — runs against the built binary, not source.
- Compose tests: `tests/compose/` — topology + assertions.
- Fixtures: `tests/fixtures/` — static inputs; no generated artifacts committed.
- Generated test certs: `tests/fixtures/gen-certs.sh`; output gitignored.

## JUnit XML and Coverage

- Unit test runner MUST emit JUnit XML (`gotestsum --junitfile` or equivalent).
- Upload JUnit XML as a workflow artifact for test history and flake detection.
- Coverage profile MUST be produced on every unit test run.
- `make coverage` prints: total %, uncovered statement count, total statement count.
- `make ci-coverage-delta` compares PR head coverage against the merge-target base branch;
  fails if coverage drops beyond the configured threshold.

## Test Modification Policy

Test files are protected. Do not modify test files without explicit prior authorization.

When a test fails, the correct response is to find and fix the root cause in production code —
not to adjust the test to pass. A failing test is a signal, not an obstacle.

Exceptions require explicit approval:

- The test itself contains a bug.
- The tested behavior was intentionally changed and the test must track the new contract.
- A new test is being added.

## FIPS Compatibility

Tests that use `InsecureSkipVerify`, self-signed certs via `httptest`, or non-FIPS algorithms
MUST be guarded with a FIPS skip:

```go
if os.Getenv("GOFIPS140") != "" {
    t.Skip("skipping under FIPS")
}
```

Do not leave FIPS-incompatible tests unguarded; they will fail CI on FIPS builds.
