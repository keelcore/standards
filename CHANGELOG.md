# Changelog

All notable changes to keelcore/standards are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows
[Semantic Versioning](https://semver.org/).

Breaking changes (governance removals, renamed files): major bump. New governance or expanded rules: minor bump.
Corrections, clarifications, metadata: patch bump.

---

## [Unreleased]

### Added

- `make wait-for-ci` (`scripts/release/wait-ci.sh`): waits, with progress, for the GitHub Actions runs on a commit to finish,
  then fails if any is red. The tag's publish workflow runs it first, so a red commit is never published; the host never
  waits for CI.
- `make update-pins MAJOR='NAME ...'` (`--major NAME`): moves a named pin to its newest release of any major past the
  cooldown, with the usual verification.
- `make pull-dev-image` (`scripts/dev/pull.sh`): fetches the pinned dev image onto this machine.
- `make update-pins` prints progress every 30 seconds while it verifies (`UPDATE_PINS_PROGRESS_SECONDS`): elapsed
  time, pin, image build step and latest log line for each running pin and the combined run, and a result line as each
  pin finishes.
- `make setup-apple-container` (`scripts/ci/setup-apple-container.sh`): installs Apple `container` from the signed
  installer package of its latest GitHub release, checked against the published SHA-256, Apple's signature and
  notarization, then starts the system and installs its default kernel when it has none. Runs on the Mac host; when
  the latest version and a kernel are present it changes nothing.
- Canonical image release, chart push, upload and self-verification: `make release-images`, `release-helm-push`,
  `release-upload`, `release-verify`, `release-metadata`, `release-ghcr-login`, driven by `config/release-images.local.txt`,
  `release-dockerfile.local.txt` and the workflow's repository; grype in the tool image.
- Canonical, each doing nothing without its trait: `make lint-workflows` (now in `make lint`), `lint-gosec`, `lint-licenses`,
  `lint-helm`, `lint-helm-validate`, `lint-helm-policy`, `lint-vex`, `test-unit`, `test-fuzz`, `coverage-profile`,
  `release-vex`, `release-checksums`, `dist-chmod`, `native-build`, `native-run`, `native-integrity`, with their tools in
  the tool image.
- `config/` holds tool defaults; a repository adjusts them in `config/<name>.local.txt` (`scripts/lib/tool-config.sh`).
- `templates/SECURITY.md`, `CODEOWNERS` and `dependabot.yml`; `make audit` requires all three (Rule 7).
- `.github/workflows/scorecard.yml` and `codeql.yml` are canonical: consumers carry them byte-identical, checked by
  `make verify-canonical` and synced by `make governance-refresh`. CodeQL analyzes the languages the repository holds
  (`make codeql-languages`; `config/codeql.local.txt` replaces the detection).
- `make lint-vuln` and `make setup-govulncheck`: govulncheck in every repo-owned Go module, from the tool image.
- `scripts/lib/parallel.sh`: `run_parallel` runs a function over many items at once, waits for them all, and prints each
  job's log whole.
- `update-pins --check-pins-doc FILE` (`make check-pins-doc`, also a pre-commit check): `docs/current_pins.md` lists
  exactly the pins in the tree; local, no network
- Versioned git hooks in `scripts/hooks/` (canonical, synced); `scripts/hooks/pre-commit` runs `scripts/git_precommit.sh`

### Changed

- `update-pins` fetches each tool image once: pins name the image they need, the names are made unique and fetched in
  parallel, and the checks start only when every fetch has finished. `run.sh` gains `--image-ref` and `--fetch-image`.
- GitHub Actions move to a new major like any other update: `update-pins` writes new action and runner image majors past
  the cooldown, for CI to prove. A `0.y.z` update is no longer treated as a major (semver.org: the major is the first
  number).
- A git commit never fetches or stops for the dev image: without it on the machine, or with no pin yet, the hook skips
  those checks and says so, and CI runs them, so a new image can bootstrap.
- `setup-helm.sh`, `setup-kubeconform.sh`, `setup-kubescape.sh`, `setup-zizmor.sh` and `setup-grype.sh` install in the dev
  image only; their Homebrew paths are gone.
- **Breaking:** every make target is verb-first (`governance/ci.md`, Make Targets), and `make audit` enforces it (Rule 8).
  Old canonical names print the new name and fail, for example `release-sign` to `sign-release`, `dev-image-push` to
  `push-dev-image`, `pins-doc` to `generate-pins-doc`, `integration-test` to `test-integration`.
  `unit-test` and the Go runner
  join as `test-unit`.
- `make create-release` decides on the pin status committed in `docs/current_pins.md` (`update-pins --from-pins-doc`),
  with no network query, so an upstream change after the commit cannot block a commit that was current. A tree with
  pins and no such document, or a document out of step with the tree, blocks the release (`make pins-doc`).
- `sign.sh` signs its artifacts concurrently; `SHA256SUMS` is signed last.
- `update-pins` verifies every pin locally: an image pin, and any kind without a specific target, by the project's
  combined targets; the Go toolchain by `test` in the tool image on every host; only runner labels stay on CI.

- `scripts/dev/run.sh` uses the published `ctx-<hash>` image of the tree's build context when `image.ref` pins another
  one, and builds locally only when that context is unpublished (`dev_published_ref` in `scripts/lib/dev-image.sh`)
- `dev-image.yml` is a reusable workflow, no longer triggered by a push: `ci.yml` calls it first on every push to
  `main`, and every tool job `needs:` it, so each build context is published once and pulled everywhere else
- A tool-image pin (`devimage`) never blocks `make create-release`: an unpublished build context is a hold
  (`run.sh` builds it locally); once published it is stale and `make update-pins APPLY=1` pins it
- `make install-hooks` sets `core.hooksPath scripts/hooks`: one setting serves a clone, every worktree and a
  submodule checkout
- `make create-release` tags the approved `HEAD` and pushes the tag, and nothing else: no release commit, no
  CHANGELOG cut, no `image.ref` pinning. Pins and `docs/current_pins.md` are committed before the release
- `make update-pins APPLY=1` rewrites `docs/current_pins.md` from the pins it wrote
- The release notes and the bump level take the `CHANGELOG.md` `[Unreleased]` entries added since the previous tag
- The release notes name the tool-image SBOMs by file (`<repository>-<image>.spdx.json`)

### Fixed

- A commit checks with the image that holds its tree's tools, pinned or built locally. Without one on the machine, the hook
  skips those checks and says so, and CI runs them, so changing a tool never blocks a commit.
- A git hook or any `run.sh` run in a worktree or submodule no longer risks reverting the working tree: each run has its
  own snapshot, removed when it ends, and a writable run copies back only what its command changed, keeping newer edits.
- `update-pins` no longer holds the console open for the rest of a progress interval when a run ends.
- The tables in `governance/ci.md` and the long lines in `CHANGELOG.md` pass markdownlint 0.49.1.
- `publish.sh` builds on the published `.standards` tool image when `image.ref` pins another context, as `run.sh` does:
  both use `dev_resolve_ref`, so a consumer's image no longer waits for a pin and a second release.
- `tests/release-images.bats` passes on CI: the tests use their own repository, not the workflow's `GITHUB_REPOSITORY`.
- `make update-pins` lists its report by status, what needs action first; an unpublished tool image no longer prints a
  curl error; the Helm pin resolves.
- `sign.sh` gives each concurrent signature its own cosign cache; they collided writing the shared TUF metadata.
- The PyPI publish job waits for the packages only; it no longer hangs on the publish action's attestation files.
- Each publish job waits until its registry serves everything of the version (`make release-wait-published`), so the
  release job reads metadata after the upload has finished.
- `release-assets.sh` waits for npm's tarball and attestations, as it does for the version, and names whichever never
  appears; a release no longer fails with only "no published artifacts found" while they propagate.
- `run.sh` `sync_back` passes over submodule entries, so a writable run from a worktree of a repo with submodules no
  longer fails after copying its edits back.

## [0.10.9] - 2026-11-04

### Added

- `scripts/dev/publish.sh` runs the project hook `scripts/dev/publish.local.sh MODE` after each mode, when the
  repository holds it
- `make check-clean-tree` (`scripts/ci/check-clean-tree.sh`): the last step of every CI job that runs tool targets;
  the job must leave the working tree exactly as checked out
- Audit Rule 6: no runtime tool installs in workflows (`actions/setup-*`, `make setup-*`); host jobs are listed in
  `.runtime-install-exceptions` with their reason
- `update-pins` pin kind `devimage`: `containers/NAME/image.ref` is stale while the tree's build context differs from
  the pinned one; apply pins the published context by digest
- `release-assets.sh` takes a project's own artifacts (binaries, charts) from the hook
  `scripts/release/release-assets.local.sh TAG DIR`, and attaches the repository's `LICENSE` to every release
  (`RELEASE_LICENSE` names the SPDX id when no package manifest does)
- `governance/devsecops.md` § Immutable Tool Images
- `make create-release` pins each published tool image (`containers/NAME/image.ref`) by digest in the signed release
  commit, so no separate `make dev-image-ref` commit is needed

### Changed

- Pins: cosign 3.1.4 (tool image), setuptools 84.2.1 (PyPI build)
- In a consumer, a pin located in a canonical file (byte-identical to its `.standards` copy) is held by
  `.standards`: it never blocks the consumer's release gate and is never applied there
- `update-pins` verifies each pin in a worktree of the staged tree (HEAD plus the index; submodules at their staged
  commits plus uncommitted changes), and an interrupted run stops every verification it started and removes every
  worktree it created
- `scripts/dev/run.sh` snapshots of worktrees and submodules: each submodule is a standalone snapshot of its own,
  staged deletions are removed, and the snapshot's index matches its files
- Inside a git hook, the tool-image scripts drop git's hook environment (`GIT_INDEX_FILE`, `GIT_DIR`, ...) before
  running git in other repositories, and never build an image (a changed build context is checked with the pinned
  image); a TTY is requested only when stdin and stdout are both terminals
- `run.sh` passes environment variables by name (`-e NAME`): no value appears in the runtime's argument list
- Registry credentials: in CI one login per job into a per-job `DOCKER_CONFIG`, mounted read-only into the tool
  container (`sign-image.sh` no longer logs in itself); `publish.sh local` logs Apple `container` in only when it
  holds no credential and never logs out
- Apple `container` builds are sized by `KEELCORE_BUILD_CPUS` (4) and `KEELCORE_BUILD_MEMORY` (8g); a builder
  running at another size is restarted at that size
- Tool images: one `COPY` + `RUN` per tool; setup scripts install only while the image is built
  (`KEELCORE_IMAGE_BUILD`) and otherwise check the baked tool; staticcheck is the checksum-verified release binary
  (2026.2.2, module v0.8.2) instead of `go install`
- `dev-image.yml` checks out submodules (a consumer's Makefile includes `.standards`)
- Release notes describe the provenance files the release actually carries; build-environment SBOMs are named
  generically

## [0.10.8] - 2026-11-03

### Changed

- `update-pins` discovery reads metadata only and resolves pins in parallel (`UPDATE_PINS_RESOLVE_JOBS`, default 16):
  GitHub releases through GraphQL (tag and date of the newest releases; the REST list carries every asset, 13.5 MB for
  cosign), the latest npm, PyPI and Go version first (`dist-tags`, the PyPI releases feed, the Go proxy's `@latest`),
  a short version list only when the latest is inside the cooldown or a new major, Node from `nodejs/node`'s
  releases, and the Go toolchain by probing the next releases. A full check of this repository took 223 s; it takes
  about 20 s

## [0.10.7] - 2026-11-03

### Added

- The GitHub Release carries each artifact's provenance as its registry published it: npm's attestations
  (`*.npm-attestations.json`), PyPI's provenance (`*.pypi-provenance.json`), GitHub's build attestations by digest
  (`*.github-attestations.json`) and the Go checksum database record (`*.zip.sumdb.txt`), each signed and in
  `SHA256SUMS`
- Build-environment SBOMs list the pinned tools syft cannot identify (shellcheck, a static binary; bats, a script
  install), from the tag's installers (`sbom.sh --tools`)

### Changed

- `scripts/dev/run.sh` gives an Apple container 4 GB (`KEELCORE_DEV_MEMORY`); its default is 1 GB

## [0.10.6] - 2026-11-03

### Fixed

- `LICENSE` (MIT, Copyright (c) 2026 Paul Charlton): the packages declared MIT but carried no license text; the
  npm tarball, the wheel, the sdist and the Go module now ship it
- The GitHub Release job failed for v0.10.5: it took the PyPI publish action's attestation files for packages. It now
  fetches every artifact from its registry (npm integrity, PyPI sha256, the Go checksum database via
  `go mod download`), reads the tag's own CHANGELOG, pins and image refs, and runs as `github-release.yml`, which
  `publish.yml` calls and which can be dispatched for any published tag
- `scripts/dev/run.sh` snapshots fetch tags, so tag-based targets work from a submodule

## [0.10.5] - 2026-11-03

### Added

- A GitHub Release for every tag (`publish.yml` job `release / github`, after npm, PyPI and Go publish): the
  published files (npm tarball, wheel, sdist, the Go module zip from the proxy), one SPDX SBOM per artifact, one
  build-environment SBOM per pinned tool image, `current_pins.md`, `SHA256SUMS` and a keyless cosign bundle per
  file; notes from the signed tag message, the version's CHANGELOG section and the pins table; the job ends by
  verifying every checksum and signature against the workflow identity (`make release-assets`, `release-github`,
  `release-verify-blobs`; `governance/ci.md` v1.6.0)
- `create-release` moves the `[Unreleased]` entries under `## [X.Y.Z] - <date>` in a signed release commit, tags that
  commit, and pushes both atomically

### Changed

- `scripts/release/sbom.sh` writes one SBOM per published artifact (`--name`, `--version`, `--license`, targets), each
  cataloged by its own ecosystem's metadata, plus SBOMs of tool images by digest; it no longer scans the source tree
  (the v0.10.4 SBOM listed 245 npm and 12 PyPI build-tool packages that ship in no artifact, and named nothing)
- `npm-publish.sh` publishes the tarball it packs into `target/dist/`; the sdist carries only `governance/`, the
  README, the CHANGELOG and `pyproject.toml`; the dev image adds `unzip`

### Fixed

- `make dev-image-publish` wrote no `image.ref` after a successful push: an empty array under `nounset` (bash 3.2)
  aborted the digest lookup; inside a tool image, image names came from the mount path (`/work`) instead of the
  repository (`run.sh` passes `KEELCORE_DEV_REPO`)
- CHANGELOG: v0.10.1–v0.10.4 shipped without their sections; their entries now sit under each release, by the tag
  whose `[Unreleased]` first held them

## [0.10.4] - 2026-11-03

### Fixed

- `scripts/dev/run.sh` passes every `GITHUB_*`, `RUNNER_*` and `ACTIONS_*` variable into the tool image. npm builds
  its provenance statement from that context; with only a fixed list passed, the v0.10.3 npm publish sent
  `undefined/keelcore/standards` and the registry rejected it (422), so v0.10.3 is not on npm

## [0.10.3] - 2026-11-03

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

### Changed

- Pins refreshed (`make update-pins APPLY=1`; each verified alone, then together with `make lint audit test`):
  actions/attest-build-provenance v4.2.2, actions/checkout v6.1.0, actions/upload-artifact v7.0.2, Node 22.23.4
  (`.nvmrc` and the dev image's node base), npm 11.21.1, setuptools 84.2.0, cosign 3.1.3, gitleaks 8.30.1, syft 1.55.0.
  `docs/current_pins.md` lists every pin

### Fixed

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
- `scripts/lint/utc.sh` lists files through `source_files` (`scripts/lib/paths.sh`), so nested vendored trees listed
  in `.nolint` are skipped like every other linter's
- `scripts/release/sign.sh` header: it writes a Sigstore bundle (`<artifact>.bundle`) per artifact, not `.sig` files

## [0.10.2] - 2026-11-01

### Added

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

- Workflows: `actions/checkout` runs with `persist-credentials: false`; the publish jobs run without
  `setup-go` / `setup-node` caches (a poisoned cache must not reach a release); npm for trusted publishing is pinned
  (`npm@11.21.0`) instead of `npm@latest`

## [0.10.1] - 2026-10-31

### Fixed

- PyPI publish: `pypa/gh-action-pypi-publish` v1.13.0 → v1.14.3. Its bundled `packaging` 25.0 rejected the wheel's
  metadata version 2.5 (written by current hatchling), so v0.10.0 never reached PyPI; v1.14.3 bundles `packaging` 26.2,
  which accepts 2.5

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
