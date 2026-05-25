# Testing Standards

These rules govern all test code and test infrastructure in this project. They are non-negotiable.

**Maturity:** Required **Version:** 1.1.0 **Last Reviewed:** 2026-05-24

## Core Principle

Unit tests do not cross system boundaries.

A system boundary is anything that requires a network peer, an OS service, or an external process. If a test needs one
of those, it is an integration test and belongs in BATS, Compose, or a cluster-level suite — not in a `_test.go` file.

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

Mocks replicate the mock author's understanding of a contract at a point in time. When the real system changes, mocks
silently pass. Real tools catch contract drift.

Acceptable alternatives to real systems:

- In-process test servers (e.g. `httptest.NewServer`) for HTTP — acceptable in unit tests.
- Real test daemons (pebble, OPA, syslog) — required in integration tests.
- Never: mocked network peers, mocked OS services, mocked external processes.

## Test Suite Structure

Every project MUST define the following test layers. Names and Makefile targets are fixed.

| Layer       | Makefile target         | Scope                                  | External deps        |
| ----------- | ----------------------- | -------------------------------------- | -------------------- |
| Unit        | `make unit-test`        | In-process logic; no system boundaries | None                 |
| Integration | `make integration-test` | Binary + real peers                    | Test daemons on PATH |
| Compose     | `make test-compose`     | Full stack via Docker Compose          | Docker               |
| Kubernetes  | `make test-k8s`         | Helm deploy + pod probes               | kind / Docker        |

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
- `make ci-coverage-delta` compares PR head coverage against the merge-target base branch; fails if coverage drops
  beyond the configured threshold.

## Coverage Regression Policy

**Per-file coverage SHALL NEVER decrease.** This is a non-negotiable, unwaivable invariant of every change. No
`STANDARDS_OVERRIDES.md` entry can permit a regression; there is nothing to override because the rule is procedural,
not policy.

Granularity, baseline, comparison:

- The unit of comparison is **per-file line coverage**: the ratio `LH / LF` for each `SF:` record in the LCOV report.
  Totals or aggregate percentages are insufficient — a per-file improvement that masks a per-file regression is a
  violation.
- The baseline lives at `tests/coverage-baseline.lcov` in the consumer repo, tracked in git. It is updated only as
  part of a change that strictly increases (or holds) coverage on every file present in both the baseline and the
  current report, AND that meets the new-file floor (below) for every file added in that change set.
- Comparison is `current vs baseline`:
  - **Existing files** (`SF:` present in both): assert
    `current.LH/current.LF >= baseline.LH/baseline.LF`. Equal or higher passes; lower fails.
  - **New files** (`SF:` present only in current): assert
    `current.LH/current.LF >= 0.95`. New files MUST land at ≥ 95% coverage. Files added with less than 95% per-file
    coverage cause the gate to fail. This is an absolute floor — no override.
  - **Deleted files** (`SF:` present only in baseline): drop out of comparison, but the baseline entry MUST be removed
    in the same change set; otherwise the audit flags a stale baseline.
- The enforcement target is `make ci-coverage-no-regression`. The implementation lives at
  `scripts/test/coverage-no-regression.sh` (canonical; shipped). It consumes the LCOV from `make coverage` and the
  baseline at `tests/coverage-baseline.lcov`; exits non-zero on any per-file regression OR new-file floor violation.

Two consequences when a regression is detected:

1. **CI gates the merge.** `make ci-coverage-no-regression` exits non-zero. The PR is rejected.
2. **Assistant workflow procedure.** An assistant detecting a regression in its own work-in-progress MUST NOT present
   the change for human approval. It MUST revert the offending change set, then report to the human: the file(s) whose
   coverage decreased, the prior and current percentages, and the revert. The decision about next action belongs to
   the human; the decision about whether to present is procedural and not the assistant's to make.

Edge cases:

- **Removing a file entirely is allowed.** When the file is removed, its baseline entry is removed in the same change
  set. The comparison sees no `SF:` for that path in either side.
- **Splitting a file** (one file becomes two) is treated as removal + two new files. Each resulting file is subject
  to the new-file 95% floor from its first measurement; the original baseline entry is removed in the same change set.
- **Baseline initialization** (the first run of `make coverage-baseline-init` against a repo with no prior baseline)
  is exempt from the 95% new-file floor — every file is captured at its current ratio to seed the baseline. From the
  second change set onward the rule binds in full: existing-file no-regression PLUS new-file 95% floor.
- **Non-determinism in coverage tooling** (per-file numbers that drift across runs without code change) is itself a
  violation. The cause must be fixed before the baseline can be trusted.

This applies to every language with a per-file coverage report: Go (`go test -coverprofile`), Rust (`cargo-llvm-cov`
LCOV), and any other.

## Test Modification Policy

Test files are protected. Do not modify test files without explicit prior authorization.

When a test fails, the correct response is to find and fix the root cause in production code — not to adjust the test to
pass. A failing test is a signal, not an obstacle.

Exceptions require explicit approval:

- The test itself contains a bug.
- The tested behavior was intentionally changed and the test must track the new contract.
- A new test is being added.

## FIPS Compatibility

Tests that use `InsecureSkipVerify`, self-signed certs via `httptest`, or non-FIPS algorithms MUST be guarded with a
FIPS skip:

```go
if os.Getenv("GOFIPS140") != "" {
    t.Skip("skipping under FIPS")
}
```

Do not leave FIPS-incompatible tests unguarded; they will fail CI on FIPS builds.
