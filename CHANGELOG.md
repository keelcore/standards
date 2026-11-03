# Changelog

All notable changes to keelcore/standards are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[Semantic Versioning](https://semver.org/).

Breaking changes (governance removals, renamed files): major bump. New governance or expanded rules: minor bump.
Corrections, clarifications, metadata: patch bump.

---

## [Unreleased]

### Added

- Tool images (`governance/ci.md` v1.5.0 "Tool Images"): every tool target runs in an immutable image, locally
  (Apple `container`) and in CI (docker), with the repository mounted read-only and its output directories writable
  (`containers/writable`; default `target/`), a submodule as a standalone /tmp snapshot (`scripts/dev/run.sh`;
  `--writable` for `format`, `coverage-baseline-init` and `release-npm`). `containers/dev`
  bakes in Go 1.27.3, Node 22.23.3, npm 11.21.0 (lockfile), shellcheck, bats, markdownlint, staticcheck, gitleaks,
  syft and cosign; `containers/pypi` carries CPython 3.12.15 and the hash-locked build tooling. Hosts install no
  tools: workflows drop every `setup-*` step and `actions/setup-go|node|python`, and the macOS Homebrew installs are
  gone. `dev-image.yml` publishes each image to GHCR by build context (`ctx-<hash>`), per-architecture native builds
  joined into a signed multi-arch index; `make dev-image-ref` pins it by digest (`containers/NAME/image.ref`);
  `make dev-shell` opens a shell in the image. New canonical installers `setup-gitleaks.sh` and `setup-cosign.sh`
  (per-architecture SHA-256); syft gains its arm64 SHA-256; `secret-scan.sh` no longer installs at run time
- `update-pins`: packages a Containerfile installs at build time are pinned by its image digest once
  `image.ref` exists, and float until then

- `make update-pins` verifies: each stale pin is applied alone in a throwaway git worktree (submodules from the local
  clones, private tool bin and npm prefix), exercised by the make targets for its kind, and rolled back — a failing pin
  never stops the others — then all passing pins run together (`lint audit test`, or the project's combined targets).
  Appliers for every kind: action SHA + version comment, image digest, release tool version + committed SHA-256
  (remapped through the digests GitHub publishes per asset, no download), Go tool, toolchain, npm, Node, and Go
  modules (`go get`, `go mod tidy`, `go mod vendor`). `APPLY=1` writes the passing pins only after the combined run
  passes; `DISCOVER=1` reports only; `REPORT=FILE` saves the report. Each stale or failing pin lists the consequence of
  staying on it. The hook contract adds `verify`, `combined`, `apply` and `cleanup`
- Dependabot union in `update-pins`: open Dependabot PRs and alerts join the candidates; the newer candidate wins and a
  `SOURCE` column shows `update-pins`, `dependabot` or `both` (image tag suggestions stay notes)
- `create-release` pin gate: stale pins block the release; `--allow-stale-pins "<reason>"`
  (`make create-release ALLOW_STALE_PINS=...`) authorizes it and records the override in the signed tag
  (`Pins-Override`, `-By`, `-At`, `Pins-Stale` trailers) and `<git-dir>/release-audit.log`; every tag carries a
  `Pins:` summary
- `.github/workflows/update-pins.yml` (`workflow_dispatch`): the full verification on Linux, report and logs uploaded
- `governance/ci.md` v1.3.0 "Pin Refresh"; `governance/release-policy.md` v1.2.0 "Stale Pins" and the pre-release
  `update-pins` step
- `.nvmrc` pins the exact Node LTS release (`22.23.3`), not the major
- `make lint-go` runs `go vet` and `staticcheck` in every repo-owned Go module after the gofmt check;
  `scripts/ci/setup-staticcheck.sh` and `make setup-staticcheck` (pinned v0.8.2) are canonical
- Everything else pinned exactly (`governance/ci.md` v1.4.0 "Pin Refresh"): the Go toolchain (`toolchain go1.27.3`;
  `go 1.22` stays the consumers' minimum); runners by image label (`ubuntu-24.04`, never `*-latest`); Python
  (`.python-version` 3.12.15); the PyPI build tooling as a hash-locked closure
  (`scripts/release/pypi/requirements-build.txt`, installed `--require-hashes`, built `--no-isolation`; exact
  build-system requirements in `pyproject.toml`); markdownlint from a committed lockfile (`scripts/ci/markdownlint/`,
  `npm ci` into a cache keyed by the lockfile; `scripts/lib/markdownlint.sh`); shellcheck (v0.11.0, per-arch
  SHA-256) and bats (v1.14.0, verified commit) on Linux instead of unversioned apt packages
- `update-pins` kinds `runner` (newer images report-only), `python`, `pypi` (hashes follow the version), `npmlock`
  (lockfile regenerated outside the cooldown), and release tags cloned with git (`*_COMMIT` follows the version);
  `*-latest` runners, npx and pip installs without a version or hashes, and package.json ranges report as `unpinned`

- `make update-pins` (`scripts/release/update-pins.sh`): discovers every pinned external input (workflow action SHAs,
  image digests, GitHub-release tools, Go tools, Go toolchain, go.mod requirements, npm, Node) plus inputs that float
  unpinned (`@latest`, apk/apt packages without a version, Homebrew, FROM/`image:` without a digest), and resolves
  each pin's newest eligible candidate from published metadata only: no prereleases, 14-day cooldown (2 days for a
  Go toolchain patch), new majors and 0.x minors report-only, failed lookups `unresolved`. Discovery only; nothing is
  applied. Project pins and holds come from `scripts/release/update-pins.local.sh pins|holds`.
  `tests/update-pins.bats` covers every kind offline through `UPDATE_PINS_FIXTURES`

- Lint errors and warnings are never suppressed in source code, in any language, current or future; only the
  linter's git-versioned configuration may turn a rule off. `governance/coding.md` v1.1.0 states it as "Static
  Analysis Configuration" (replacing "Static Analysis Suppression", which recommended `//lint:ignore`).
  `scripts/lint/forbid-lint-suppressions.sh` now scans every repo-owned file, whatever its type, against a
  `DIRECTIVES` catalog of known linters' suppression syntax (previously shellcheck in `*.sh` only); markdown is
  scanned for markdownlint's comment directive only. Covered by `tests/lint-suppressions.bats`

- `governance/devsecops.md`: severity-ranked rules for repository controls (rulesets, environments, secret scanning),
  release integrity (sign before alias, idempotent signing, per-image SBOM and provenance), scanning gates
  (govulncheck, CodeQL/gosec, image scan, fuzzing), digest-pinned base images, chart defaults, and UTC-only timestamps;
  indexed in `README.md` and the Claude, Copilot and Cursor adapters
- `scripts/lint/utc.sh` and `make lint-utc` (part of `make lint`): rejects shell `date` without `-u` and Go
  `time.Local`, `.Local()` and `time.Now().Format` outside tests
- `Makefile.canonical` exports `TZ := UTC`, so every recipe runs in UTC; workflows set `TZ: UTC`
- `.canonical-exclude`: a consumer lists canonical scripts it never runs; `verify-canonical` and `governance-refresh`
  skip them, and audit Rule 5 accepts their targets pointing at a missing file (`governance/ci.md` v1.2.0)

### Changed

- Pins refreshed (`make update-pins APPLY=1`; each verified alone, then together with `make lint audit test`):
  actions/attest-build-provenance v4.2.2, actions/checkout v6.1.0, actions/upload-artifact v7.0.2, Node 22.23.4
  (`.nvmrc` and the dev image's node base), npm 11.21.1, setuptools 84.2.0, cosign 3.1.3, gitleaks 8.30.1, syft 1.55.0.
  `docs/current_pins.md` lists every pin
- Workflows: `actions/checkout` runs with `persist-credentials: false`; the publish jobs run without
  `setup-go` / `setup-node` caches (a poisoned cache must not reach a release); npm for trusted publishing is pinned
  (`npm@11.21.0`) instead of `npm@latest`

### Fixed

- `scripts/dev/run.sh` passes every `GITHUB_*`, `RUNNER_*` and `ACTIONS_*` variable into the tool image. npm builds
  its provenance statement from that context; with only a fixed list passed, the v0.10.3 npm publish sent
  `undefined/keelcore/standards` and the registry rejected it (422), so v0.10.3 is not on npm
- `update-pins` reads the GitHub token once per run (`GITHUB_TOKEN`, else one `gh auth token`) and exports it; it ran
  `gh auth token`, a keychain read, for every GitHub API request
- `scripts/dev/run.sh`: a git worktree is mounted as a standalone /tmp snapshot like a submodule (its `.git` points
  outside it), the working directory is computed from the physical path (macOS `/tmp` and `/var` are symlinks), and
  image tags and snapshots are named by the repository's shared git directory, so every checkout reuses one image
- `make dev-image-publish` (macOS): builds every unpublished tool image for linux/amd64 and linux/arm64 with Apple
  `container`, pushes it and pins it in `image.ref`, so one commit carries published, digest-pinned images; the
  dev-image workflow then signs them (`sign-image.sh` skips an image this repository already signed)
- `update-pins` verifies stale pins in parallel, each in its own worktree (`UPDATE_PINS_JOBS`, default 4); a pin that
  fails is retried once after every other pin has had its first run; `make pins-doc` (`--pins-md FILE`) writes
  every pin and floating input as a Markdown table to `docs/current_pins.md`
- `update-pins`: tool, Node, npm and PyPI pins verify in the tool images on every host (`make setup-<tool>` runs
  the installer in the dev image), no longer only on Linux; applying a Node pin moves every `node:<version>-…`
  base image to the new version's digest, so the image that supplies Node follows `.nvmrc`
- Audit Rule 5 checks the script a tool-image recipe runs (`bash scripts/dev/run.sh ... bash scripts/X.sh`), not
  only the runner
- Markdown lint ran `npx --yes markdownlint-cli2` at whatever version npm served, because `setup-markdownlint`
  installed a different package (`markdownlint-cli`); it now runs the pinned, lockfile-installed markdownlint. The
  unused `markdownlint-cli2` devDependency is gone from `package.json`
- `sbom.sh` install hints name `make setup-syft` instead of piping syft's `main` install script to `sh`
- `update-pins` retries every failed fetch (`--retry-all-errors`: dropped HTTP/2 streams and timeouts were reported
  as `unresolved`), and skips the project hook when scanning (its quoted patterns were reported as pins)
- PyPI publish: `pypa/gh-action-pypi-publish` v1.13.0 → v1.14.3. Its bundled `packaging` 25.0 rejected the wheel's
  metadata version 2.5 (written by current hatchling), so v0.10.0 never reached PyPI; v1.14.3 bundles `packaging` 26.2,
  which accepts 2.5
- `scripts/lint/utc.sh` lists files through `source_files` (`scripts/lib/paths.sh`), so nested vendored trees listed
  in `.nolint` are skipped like every other linter's
- `scripts/release/sign.sh` header: it writes a Sigstore bundle (`<artifact>.bundle`) per artifact, not `.sig` files

## [0.10.0] - 2026-10-30

### Added

- Architecture Review Board governance (`governance/arb.md`) — membership, quorum, tie-breaking, escalation
- RFC workflow (`docs/rfc/RFC-0000-template.md`) — full Draft → Implemented lifecycle
- DACI metadata fields on ADR template and all existing ADRs (Driver, Approver, Contributors, Informed, Supersedes,
  Superseded By)
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
- Canonical `scripts/release/create-release.sh` and `make create-release` (`FORCE=vX.Y.Z`, `DRY_RUN=1`): signed
  annotated release tag; the bump level comes from the repo's own `scripts/release/create-release.local.sh`
  (patch when absent), resolved from the git toplevel of the repo being released
- `--dry-run` for `create-release.sh`: computes and prints the version and tag message without tagging or pushing
- Standards bump hook: `CHANGELOG.md` `[Unreleased]` decides the level (Removed → major, Added/Changed → minor, else
  patch)
- BATS suites in `tests/` (`make integration-test`, CI job `test / bats`): create-release driver, CHANGELOG hook, and
  `*.local.sh` exclusion

### Changed

- `governance/ci.md` "Version Computation": tags are the only version source; the bump level comes from the project's
  hook, with keel's schema diff and the standards CHANGELOG hook as examples
- `verify-canonical` and `governance-refresh` skip `*.local.sh`: hooks belong to the repo that holds them and are never
  compared, copied or overwritten
- `governance/release-policy.md` is now project-agnostic: the hook contract, pre-1.0 demotion, `DRY_RUN=1`, and a
  "Project Customization" section — what a project may customize (bump hook, `create-release-local` target, its own
  release-policy doc, which incorporates this one by reference) and what it may not

### Removed

- `VERSION` file (nothing read it; tags are the only version source)

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
