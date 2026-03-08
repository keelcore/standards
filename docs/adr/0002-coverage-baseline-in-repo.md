# ADR-0002: Code Coverage Baseline Stored in Repository

**Date:** 2026-03-09
**Status:** Accepted

## Context

PRs that reduce code coverage must be automatically rejected. Enforcing this requires CI to know
the current coverage baseline — a value that persists across runs and changes over time as code evolves.

Several storage mechanisms were evaluated. The choice determines auditability, operational complexity,
external dependencies, and behavior under failure conditions.

## Decision

The coverage baseline is stored as a committed file in each consuming repository at
`coverage/baseline.json`.

```json
{
  "total": 87.4,
  "updated": "2026-03-09T12:00:00Z",
  "commit": "abc123def456"
}
```

**Write path:** After every successful merge to the default branch, a post-merge CI job recomputes
coverage and commits an updated `coverage/baseline.json`. The commit is attributed to the CI bot
identity, signed, and uses the message `chore: update coverage baseline to XX.X%`.

**Read path:** The PR coverage job reads `coverage/baseline.json` from the base branch via
`git show origin/main:coverage/baseline.json` before comparing against the PR's computed coverage.

## Consequences

**Positive:**
- Full audit trail via git blame and log — every baseline change is attributed, timestamped,
  and linked to the merge commit that caused it.
- Zero external dependencies — no coverage service, no separate database, no API keys, no
  third-party availability risk.
- Works in air-gapped and FIPS environments without modification.
- Baseline is always consistent with the code at that commit; history is queryable.
- Developers can inspect the baseline locally without any tooling beyond `git`.
- The baseline update is a normal commit — it can be reverted if a bad merge inflated coverage
  artificially (e.g. deleted tests).

**Negative:**
- The repository accumulates baseline update commits on the default branch. These are low-signal
  noise in `git log`. Mitigated by using a consistent commit message prefix (`chore: update coverage`)
  that can be filtered.
- A CI bot identity requires a machine account with write access to the default branch. This is
  a credential that must be managed and rotated.
- If the post-merge baseline update job fails, the baseline drifts until the next successful merge.
  Mitigated by alerting on baseline update job failure and by the fact that a stale baseline is
  conservative (it does not silently lower the bar).
- Branch protection rules must allow the CI bot to push directly to the default branch for baseline
  updates. This is a narrow, auditable exception to the standard PR requirement.

## Alternatives Considered

### GitHub Actions Cache
Store baseline as a cache entry keyed to the default branch.

Rejected because: cache entries are not version-controlled, have a 7-day TTL requiring active
maintenance, are not auditable, can be evicted under storage pressure, and are not accessible
outside GitHub Actions (developers cannot check the baseline locally).

### GitHub Artifact
Upload baseline as a workflow artifact after each merge.

Rejected because: artifacts expire (default 90 days), require artifact ID resolution to fetch
the latest, are not version-controlled, and add workflow complexity to locate the most recent
baseline artifact across runs.

### External Coverage Service (Codecov, Coveralls, SonarCloud)
Push coverage data to a third-party service; query the API in PR CI.

Rejected because: introduces an external dependency that can be unavailable, requires API keys
rotated and managed as secrets, has cost at scale, and creates a data egress channel for internal
coverage metrics. Acceptable as a supplementary visualization layer, not as the enforcement gate.

### Dedicated `coverage` Branch
Store baseline in a long-lived orphan branch (similar to `gh-pages`).

Rejected because: orphan branches require non-standard git operations, are confusing to
contributors, and provide no meaningful benefit over committing to the default branch given
that the file is small and the commit cadence is low.

### Environment Variable / Repository Variable
Store the baseline as a GitHub repository variable updated by CI.

Rejected because: repository variables have no history, no blame, no rollback, and no local
accessibility. A variable change is invisible in the code review workflow.

## Implementation Notes

- `scripts/test/coverage.sh` computes coverage, reads the baseline, compares, and exits non-zero
  on regression. It is the canonical entry point for both CI and local use.
- The CI bot push uses a fine-grained Personal Access Token (PAT) or GitHub App installation
  token scoped to `contents: write` on the specific repository. It does not use `GITHUB_TOKEN`
  with branch protection bypass.
- The baseline commit is excluded from PR policy checks (commit message format, linked issue)
  via a conventional commit prefix exemption in `scripts/ci/pr-policy.sh`.
- Packages and projects that have not yet established a baseline begin at 0.0%. The first
  post-merge baseline commit sets the floor. Coverage can only move up from there without
  triggering a gate failure.