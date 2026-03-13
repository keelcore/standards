# CI Standards

These rules govern all CI workflow and script work. They are non-negotiable.

**Maturity:** Required
**Version:** 1.0.0
**Last Reviewed:** 2026-03-09

## Core Principle

CI workflow YAML is thin orchestration only. No build, test, lint, packaging, signing, or release logic lives
in YAML — it lives in `scripts/` entrypoints.

## Workflow File Responsibilities

YAML may only contain:

- Trigger selection
- Permissions
- Matrix definition
- Caching
- Environment setup (toolchain version via language version file, e.g. `go-version-file: go.mod`)
- Artifact upload / download
- Invocation of stable `scripts/` entrypoints

## Trigger Requirements

- Every workflow and every job within a workflow must be manually triggerable via `workflow_dispatch:`.
- `workflow_dispatch:` is a required field on every workflow file without exception.
- No workflow is merged without `workflow_dispatch:` in the trigger block.
- Manual triggers must accept the same inputs as automated triggers where relevant (e.g. ref, artifact version).

## Script Entrypoints

One script per concern. Scripts are the canonical entry point for all CI logic. Workflow YAML invokes them;
it does not duplicate their logic.

## Makefile Entrypoints

- Every `run:` step in workflow YAML MUST be `make <target>` and nothing else.
- No `run:` may call bash, sh, bats, go, chmod, or any tool directly.
- Each CI concern maps to exactly one Makefile target.
- Multi-command steps must be aggregated into one target; YAML calls the target.
- Setup steps (tooling, fixtures) are also Makefile targets (e.g. `make setup-bats`).
- The Makefile is the single dev-facing interface: what CI calls, a developer can call locally.
- Every `scripts/**/*.sh` file (except sourced library files under `scripts/lib/`) MUST have a
  Makefile target that invokes it — the script path must appear in a Makefile recipe.

## Universal Canonical Makefile Targets

Every project MUST define these language-independent targets. They form a stable, tool-agnostic
interface for humans and CI alike.

| Target | Responsibility |
|---|---|
| `make build` | Build the default artifact (binary, image, package). |
| `make lint` | Run all linters (format check + static analysis). |
| `make test` | Run the full test suite (unit + integration). |
| `make unit-test` | Run unit tests only. |
| `make integration-test` | Run integration/BATS/end-to-end tests only. |
| `make clean` | Remove build artifacts and generated files. |
| `make audit` | Run the CI/standards compliance auditor. |

Rules:
- These names are fixed; projects may not rename or skip them.
- Targets may delegate to other targets or scripts but must exist.
- Language-specific subtargets (e.g. `make lint-go`, `make test-unit`) are additive; they do not
  replace the universal targets.

## CI Auditor

- Every project MUST include `scripts/ci/audit-make-targets.sh`.
- The auditor enforces the three invariants:
  1. All workflow `run:` steps are `make <target>`.
  2. All `scripts/**/*.sh` files (except `scripts/lib/`) have a Makefile target.
  3. All universal canonical targets exist in the Makefile.
- `make audit` invokes the auditor.
- The auditor MUST be a required CI step (add to the workflow as `run: make audit`).
- The auditor MUST be wired into the pre-commit hook, gated on changes to
  `.github/workflows/`, `scripts/`, or `Makefile`.

## Canonical CI Scripts

Every project MUST include the following scripts. Their names and responsibilities are fixed.

| Script | Makefile target | Responsibility |
|---|---|---|
| `scripts/ci/pr-policy.sh` | `make ci-pr-policy` | PR policy gate (title, body, branch, linked issue). |
| `scripts/ci/secret-scan.sh` | `make ci-secret-scan` | Secret scanning on every PR and push to default branch. |
| `scripts/ci/dco-check.sh` | `make ci-dco` | DCO Signed-off-by trailer verification. |
| `scripts/ci/audit-make-targets.sh` | `make audit` | CI/Makefile standards compliance auditor. |
| `scripts/lint/newlines.sh` | `make lint-newlines` | Trailing newline enforcement for text files. |

## Source File Formatting Invariants

- Every `.md`, `.sh`, and `.go` file (and other text-format source files) MUST end with a single
  trailing newline (`\n`). Files without a trailing newline fail the pre-commit hook and CI.
- Enforce via `scripts/lint/newlines.sh`; auto-fix via `scripts/lint/newlines.sh --fix`.
- The pre-commit hook checks staged files; `make lint-newlines` checks the full tree.

## Build Platform vs. Target Platform

- Prefer build-once, deploy/validate-everywhere.
- Use cross-compilation to produce artifacts from a single runner.
- Use runner matrices for testing/smoke validation on target platforms, not for rebuilding.
- Per-platform builds only when required by native signing, platform-bound linkers, OS-specific packaging,
  or target-specific verification unavailable elsewhere. State the reason explicitly when doing so.
- Artifact promotion over artifact regeneration: the CI-tested artifact is the release artifact.

## Platform-Specific Finishing Steps

- Signing, notarization, and native packaging are acceptable reasons for platform matrices.
- Build the artifact in a canonical build job; use a platform matrix only for the platform-bound finishing step.
- Keep signing, notarization, and packaging steps in repository scripts; workflow YAML provides only
  orchestration, credentials, and artifact movement.

## Permissions

- `permissions: contents: read` by default on all workflows and jobs.
- `contents: write` only on the narrowly scoped release/publish job that requires it.
- `id-token: write` only on jobs that use OIDC federation or provenance attestation.
- Never grant `actions: write` or `packages: write` beyond the job that explicitly requires it.
- Set permissions at the job level, not just the workflow level, to narrow blast radius.

## Action Version Pinning

- Always pin action versions to a full commit SHA, not a tag. Tags are mutable.
  - Correct:   `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2`
  - Incorrect:  `actions/checkout@v4`
- Use Dependabot (`dependabot.yml`) with `package-ecosystem: github-actions` to keep SHA pins current.

## Toolchain Version

- Single source of truth: language version file (e.g. `go.mod`, `.nvmrc`, `.python-version`).
- Never hardcode toolchain version in workflow YAML.

## Caching

- Cache only module cache and build cache.
- Cache keys must derive from the authoritative dependency lock file (e.g. `go.sum`, `package-lock.json`).
- Do not cache opaque directories with unclear invalidation behavior.
- Fork PRs must not share cache with the base repository in ways that allow cache poisoning.

## Timeouts

- Every job must set `timeout-minutes`.
- Calibrate per job type; err on the side of generous but finite bounds.

## Supply Chain Security

### SLSA Provenance Attestation

- Release workflows must produce SLSA build provenance for all published artifacts.
- Use `actions/attest-build-provenance` or `slsa-github-generator` for SLSA Level 3 attestations.
- Attestations must be attached to GitHub Releases alongside the binaries.

### Artifact Signing

- All release artifacts must be signed with Sigstore/cosign.
- Signing lives in `scripts/release/sign.sh`; workflow YAML provides only the OIDC token and artifact path.
- Signatures and certificates are uploaded alongside binaries.

### SBOM

- Every release must include a machine-readable SBOM in SPDX or CycloneDX format.
- Generated by `scripts/release/sbom.sh`.
- Attached to GitHub Releases as a named artifact.

### Artifact Integrity Between Jobs

- Checksum artifacts before upload; verify the checksum after download in downstream jobs.
- Release artifacts ship with a `SHA256SUMS` file.
- The `SHA256SUMS` file is itself signed by the release signing key.

## Credential and Secrets Discipline

### OIDC Federation

- Use GitHub OIDC to authenticate to cloud providers instead of long-lived static credentials.
- Static secrets are acceptable only for services that do not support OIDC.

### Secret Scanning

- All PRs trigger a secret scanning job before code review.
- Secret scanning also runs on the default branch on every push.
- This job is a required status check.

### Secrets in Logs

- Scripts must never echo, print, or log secret values.
- Workflow YAML must not pass secrets as positional arguments; use environment variables.
- CI logs are treated as potentially public.

## PR Policy Compliance

### Policy Gate Job

- Every PR triggers a `pr-policy` job before human code review begins.
- This job is a required status check that runs first in the workflow DAG.

### PR Policy Checks

- Commit message format: enforce conventional commit format or project-defined conventions.
- PR title format: must match the project's defined pattern.
- PR description completeness: reject PRs with empty or template-stub descriptions.
- Linked issue: require a referenced issue number for non-trivial changes.
- Branch naming: enforce branch naming conventions.
- File size gates: reject PRs adding binary blobs or files exceeding a defined threshold.
- Forbidden file patterns: reject PRs modifying protected files without CODEOWNERS approval.
- CODEOWNERS coverage: validate that all changed files are covered by a CODEOWNERS rule.
- Secret scan: a detected secret fails the gate immediately.

### Policy Script Discipline

- All policy logic lives in a script, not in workflow YAML.
- Policy output must be machine-readable (exit code) and human-readable (stderr summary).
- Policy script must be runnable locally by developers before pushing.

## CODEOWNERS and Workflow File Protection

- `.github/CODEOWNERS` must designate a security or infra owner for:
  - All files under `.github/workflows/`
  - All files under `scripts/`
  - All dependency manifest and lock files
- Workflow file changes require CODEOWNERS review; author self-approval is not permitted.

## Fork PR Security

- Fork PRs must use the `pull_request` event trigger, NOT `pull_request_target`.
- Fork PRs must never receive access to repository secrets or write-scoped tokens.
- Use GitHub Environment protection rules to prevent fork PRs from accessing release secrets.

## Environment Protection Rules

- All release and deployment jobs must run in a named GitHub Environment.
- Named environments must have required reviewers configured.
- This creates a mandatory human gate before any artifact is published, signed, or deployed.

## Reproducible Builds

- Builds must be deterministic: same inputs produce byte-identical outputs.
- Strip debug paths and build IDs from release artifacts.
- Verify reproducibility in CI by building twice and comparing checksums.

## Test Result Reporting

- Use a structured test reporter (e.g. `gotestsum`, `pytest-junit`) to produce JUnit XML output.
- Upload JUnit XML as a workflow artifact for test history and flake detection.
- Publish a human-readable summary to `$GITHUB_STEP_SUMMARY` on each run.

## Concurrency

- Add concurrency control to cancel superseded runs for the same branch/PR.
- Concurrency group key: `${{ github.workflow }}-${{ github.ref }}`.
- `cancel-in-progress: true` for PR workflows; `cancel-in-progress: false` for main branch and release.

## Code Coverage Gate

### Requirement

- Any PR that reduces code coverage below the current baseline is automatically rejected.
- This is a required status check; it blocks merge regardless of review approval.

### Baseline Storage

- Coverage baseline is stored in the repository itself at `coverage/baseline.json`.
- The baseline is committed to the default branch after every successful merge.
- Storing in-repo provides: version history, blame, auditability, and no external service dependency.
- Format: `{ "total": 87.4, "updated": "2026-03-09T12:00:00Z", "commit": "<sha>" }`

### CI Workflow

- PR job: compute current coverage → download `coverage/baseline.json` from the base branch →
  compare → fail if current < baseline.
- Post-merge job (runs on default branch only): recompute coverage → commit updated
  `coverage/baseline.json` → push directly (no PR required for baseline updates).
- The post-merge baseline update commit must be signed and attributed to the CI bot identity.
- Baseline update commits use a conventional commit message: `chore: update coverage baseline to XX.X%`.

### Coverage Script

- Coverage computation lives in `scripts/test/coverage.sh`, not in workflow YAML.
- The script outputs a JSON report and exits non-zero if coverage drops below baseline.
- The script is runnable locally so developers can check before pushing.

### Exemptions

- PRs that only modify documentation, fixtures, or non-code assets may be exempted via PR label.
- Exemption label: `coverage-exempt` — requires explicit CODEOWNERS approval to apply.
- Exemptions are logged in CI output for audit purposes.

## Integrity

- Integrity checks run against produced artifacts, not hypothetical outputs.
- Smoke tests validate meaningful runtime behavior, not just file existence.

## Break-Glass Procedure

- A documented break-glass procedure must exist for bypassing CI when a critical security patch must ship.
- Bypass requires two senior engineers approving outside the normal flow and creation of an incident record.
- The bypass procedure must maintain an audit trail.
- Document the break-glass procedure in `docs/break-glass.md` or equivalent.

## Failure Attribution

- Keep job responsibilities narrow enough that a failure points to a clear domain.
- Job names in workflow YAML must be descriptive and match the script concern they delegate to.

## Artifact Naming

- Encode target OS, architecture, and feature profile in artifact filenames.
- Names must be explicit, stable, and reviewable.

## Release Tagging

### Versioning Specification

All version numbers follow **Semantic Versioning 2.0.0** — [https://semver.org](https://semver.org).
That document is canonical and must not be contradicted by project-specific rules.
Version tags take the form `vMAJOR.MINOR.PATCH` with no pre-release or build-metadata
extensions at this time.

Specific semver.org rules in force:

- **[Item 2](https://semver.org/#spec-item-2):** Version numbers take the form
  `MAJOR.MINOR.PATCH` — non-negative integers, no leading zeroes.
- **[Item 4](https://semver.org/#spec-item-4):** MAJOR is incremented for incompatible
  API changes; MINOR and PATCH reset to 0.
- **[Item 5](https://semver.org/#spec-item-5):** MINOR is incremented for new
  backward-compatible functionality; PATCH resets to 0.
- **[Item 6](https://semver.org/#spec-item-6):** PATCH is incremented for
  backward-compatible bug fixes only.
- **[Item 9](https://semver.org/#spec-item-9):** Major version zero (`0.y.z`) is for
  initial development. The public API is not yet stable and anything may change.
- **[Item 10](https://semver.org/#spec-item-10):** `1.0.0` defines the first stable
  public API. Subsequent increments follow the rules above without exception.

### Tagging is a Developer Action — Never CI

- Release version tags (`vX.Y.Z`) are created exclusively by developers running
  `scripts/release/create-release.sh` from a local checkout.
- CI must never create, push, or move version tags under any circumstance.
- This is a hard policy: no workflow file may contain `git tag`, `git push --tags`,
  or equivalent tag-creation steps.
- Rationale: a tag is a public commitment about what version of the software a
  commit represents. That decision requires human judgment and cannot be delegated
  to automation.

### Automatic Tag Triggering Is Permitted

- CI workflows *triggered by* a pushed tag (e.g. `on: push: tags: ['v*']`) are
  permitted and expected — they run the release pipeline once a developer has
  pushed a tag.
- The distinction is: CI reacts to tags; CI does not create tags.

### Version Computation

- Bump level (major / minor / patch) is derived from `pkg/config/schema.yaml` by
  diffing the field set at the previous tag against the field set at HEAD:
  - Removed fields → breaking change → major bump
    ([semver.org item 4](https://semver.org/#spec-item-4)).
  - Added fields (no removals) → new feature → minor bump
    ([semver.org item 5](https://semver.org/#spec-item-5)).
  - No field surface change → patch bump
    ([semver.org item 6](https://semver.org/#spec-item-6)).
- `scripts/release/create-release.sh` performs this computation, presents
  findings to the developer for approval, then creates and pushes the annotated
  tag on confirmation.
- `scripts/release/gen-schema.sh` regenerates `pkg/config/schema.yaml` from
  `cmd/config-schema/main.go` after any change to the config struct. The
  consistency suite enforces that `schema.yaml` is never stale.

### --force Override Rules

Developers may override the computed version with `--force vX.Y.Z`. Only bare
`MAJOR.MINOR.PATCH` versions are accepted; pre-release identifiers (`-alpha.1`)
and build metadata (`+sha`) are not supported by the tooling at this time.

- **Pre-1.0 (major = 0):** Only versions in the `0.x.y` range or exactly `v1.0.0`
  are accepted. Forcing `v1.1.0` or `v2.0.0` from a `0.x` base is rejected.
- **Post-1.0 (major ≥ 1):** `--force` is restricted to exact single-step increments:
  - Patch: `cur_maj.cur_min.(cur_pat+1)` — always allowed.
  - Minor: `cur_maj.(cur_min+1).0` — always allowed (e.g. internal improvements).
  - Major: only accepted when breaking changes are detected **and** the forced
    version exactly matches the auto-computed version. `--force` cannot suppress
    or redirect a breaking-change bump, and cannot skip versions.

## Do Not

- Omit `workflow_dispatch:` from any workflow's trigger block.
- Call bash, tools, or scripts directly from any YAML `run:` step — every `run:` must be `make <target>`.
- Rebuild artifacts in downstream jobs that could download a previously built artifact.
- Use per-OS build matrices when cross-compilation achieves the same result.
- Mix concerns (build + test + publish) in one script or one job.
- Silently alter triggers, required checks, or artifact semantics when making surgical CI changes.
- Pin action versions to tags instead of commit SHAs.
- Use `pull_request_target` without explicit safety guards against fork-contributed code.
- Grant elevated permissions at the workflow level when job-level scoping is possible.
- Use long-lived static credentials when OIDC federation is available.
- Echo or log secret values in scripts or workflow output.
- Skip the PR policy gate for any PR regardless of urgency (break-glass procedure exists for emergencies).
- Allow release jobs to run without environment protection and required human reviewers.
- Ship release artifacts without provenance attestation, signatures, or checksums.
- Create, push, or move version tags from CI. Tags are a developer action only.
- Bypass the `create-release.sh` script to tag manually without the schema-diff approval step.
