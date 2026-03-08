# Changelog

All notable changes to keelcore/standards are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

Breaking changes (governance removals, renamed files): major bump.
New governance or expanded rules: minor bump.
Corrections, clarifications, metadata: patch bump.

---

## [Unreleased]

### Added

- Architecture Review Board governance (`governance/arb.md`) — membership, quorum, tie-breaking, escalation
- RFC workflow (`docs/rfc/RFC-0000-template.md`) — full Draft → Implemented lifecycle
- DACI metadata fields on ADR template and all existing ADRs (Driver, Approver, Contributors, Informed, Supersedes, Superseded By)
- Maturity metadata on all governance standards (Draft | Recommended | Required | Deprecated)
- Automated ADR metadata enforcement (`scripts/check/adr-metadata.sh`)
- Automated governance metadata enforcement (`scripts/check/governance-metadata.sh`)
- RFC metadata enforcement (`scripts/check/rfc-metadata.sh`)
- PR policy gate (`scripts/ci/pr-policy.sh`) — commit format, branch naming, description completeness, secret scan
- Break-glass procedure (`docs/break-glass.md`)
- Supply chain: artifact signing (`scripts/release/sign.sh`), SBOM generation (`scripts/release/sbom.sh`)
- CI: SLSA provenance attestation, artifact signing, SBOM, and SHA256SUMS in publish workflow
- CI: concurrency control (cancel superseded PR runs), npm caching, environment protection on publish jobs
- `.github/CODEOWNERS` — coverage for workflows, scripts, governance, and manifests
- `.github/dependabot.yml` — automated action SHA pin updates
- `VERSION` file as single source of truth for standards version

## [0.1.0] - 2026-03-09

### Added

- Initial scaffold: `governance/coding.md`, `governance/ci.md`, `governance/bash.md`
- Platform architecture standards (`governance/platform.md`)
- Observability standards (`governance/observability.md`)
- Security and IAM standards (`governance/security.md`)
- Runtime and orchestration standards (`governance/runtime.md`)
- API management standards (`governance/api-management.md`)
- ADR template (`docs/adr/0000-template.md`)
- ADR-0001: Standards distributed as submodule and language package
- ADR-0002: Coverage baseline stored in repository
- ADR-0003: Architecture governance via DACI, RFC, and ARB
- ADR-0004: SPIFFE/SPIRE for workload identity
- ADR-0005: OpenTelemetry as unified observability framework
- ADR-0006: OPA as centralized authorization policy engine
- ADR-0007: Zero-downtime deployment via blue/green and canary
- ADR-0008: Rapid key rotation with 5-minute platform SLA
- ADR-0009: GitOps as declarative change management mechanism
- Multi-ecosystem publishing (Go, npm, PyPI) via GitHub Actions
- Tool adapters for Claude Code, Cursor, and GitHub Copilot
- Release scripts: `npm-publish.sh`, `pypi-publish.sh`, `go-publish.sh`
- Lint scripts: `markdown.sh`, `shellcheck.sh`
- Verify script: `go.sh`
