# Release Policy

**Maturity:** Required **Version:** 1.1.0 **Last Reviewed:** 2026-10-30

This document covers how a project that follows the keelcore standards tags and releases a version. The authoritative
policy lives in [`ci.md`](ci.md) under **Release Tagging**. This document is the developer-facing how-to that
complements that policy. It applies to every project as written; what a project may change, and where, is set out in
[Project Customization](#project-customization) below.

---

## Versioning Specification

Projects follow **Semantic Versioning 2.0.0** — [https://semver.org](https://semver.org). That document is the
canonical reference; the rules below are derived from it and must not contradict it.

Key semver.org rules in force here:

- Version numbers take the form `MAJOR.MINOR.PATCH` where each component is a non-negative integer with no leading
  zeroes.
- MAJOR is incremented for incompatible API changes; MINOR and PATCH reset to 0.
- MINOR is incremented for new backward-compatible functionality; PATCH resets to 0.
- PATCH is incremented for backward-compatible bug fixes only.
- Major version zero (`0.y.z`) is for initial development. The public API is not yet stable and anything may change at
  any time.
- `1.0.0` defines the first stable public API.
- Pre-release identifiers (`-alpha.1`, `-rc.2`, etc.) and build metadata (`+sha`) are valid semver extensions but are
  **not supported by `create-release.sh`** at this time. `--force` only accepts bare `MAJOR.MINOR.PATCH` versions.

Git tags are the only source of truth for versions. Projects keep no version file and make no version-bump commit.

**Scope of automated detection:** each project's hook detects only the surface it is written to diff. Breaking changes
it cannot see — Go type signatures, HTTP API shape, security policy, behavior semantics — are the developer's call: use
`--force` with the appropriate bump level.

---

## Core Rule: Tags Are Developer-Created, Never CI-Created

CI reacts to pushed tags to run the release pipeline. CI never creates tags. A version tag is a human commitment about
what a commit represents — that decision requires review and cannot be automated.

---

## Tooling

| Script or target                            | Purpose                                                               |
| ------------------------------------------- | --------------------------------------------------------------------- |
| `scripts/release/create-release.sh`         | Canonical (from `keelcore/standards`): compute, approve, tag and push |
| `scripts/release/create-release.local.sh`   | The project's own bump hook; never canonical, never synced            |
| `make create-release`                       | Alias for `create-release.sh` (auto mode)                             |
| `make create-release FORCE=v1.0.0`          | Alias for `create-release.sh --force v1.0.0`                          |
| `make create-release DRY_RUN=1`             | Alias for `create-release.sh --dry-run`: no prompt, no tag, no push   |
| `make create-release-local PREV_TAG=vX.Y.Z` | Run the hook alone against a previous tag                             |

---

## How Version Bumps Are Computed

`create-release.sh` gets the bump level from the hook at `scripts/release/create-release.local.sh` in the git toplevel
of the repo being released — inside a consumer, the consumer's hook, never the copy in `.standards`. The driver calls it
as `create-release.local.sh <previous-tag>`, and the hook prints two lines to stdout:

1. the bump level: `major`, `minor` or `patch`;
2. a one-line tag subject (empty means `release vX.Y.Z`).

Anything the hook writes to stderr is shown to the developer and recorded in the tag body. A non-zero exit aborts the
release. With no hook, every release is a `patch`.

| Hook reports | Meaning                               | semver.org rationale                                                       |
| ------------ | ------------------------------------- | -------------------------------------------------------------------------- |
| `major`      | Breaking change to the public surface | Incompatible API change ([item 4](https://semver.org/#spec-item-4))        |
| `minor`      | New backward-compatible functionality | Backward-compatible addition ([item 5](https://semver.org/#spec-item-5))   |
| `patch`      | No public surface change              | Bug fixes and internal changes ([item 6](https://semver.org/#spec-item-6)) |

While the major version is 0 ([item 9](https://semver.org/#spec-item-9)), `create-release.sh` demotes the bump one step
(major → minor, minor → patch) and adds `(pre-1.0 demotion)` to the tag subject. A patch stays a patch when there are
commits since the previous tag; with none, there is nothing to release.

---

## Project Customization

A project customizes releases in three places, all owned by the project. Everything else in this policy applies
unchanged.

| What                 | Where                                                  | Purpose                                          |
| -------------------- | ------------------------------------------------------ | ------------------------------------------------ |
| Bump policy          | `scripts/release/create-release.local.sh`              | Decide the bump level from the project's surface |
| Hook target          | `create-release-local` in the project's `Makefile`     | Run the hook alone; satisfies `make audit`       |
| Release how-to       | The project's `docs/release-policy.md`                 | Document the project's customization             |

### The bump hook

- It defines the project's public surface for versioning: a config schema, an API spec, exported symbols, a changelog —
  whatever a consumer of the project depends on.
- It follows the contract in [How Version Bumps Are Computed](#how-version-bumps-are-computed): called with the previous
  tag, two lines on stdout, findings on stderr, non-zero exit to abort.
- It reports the raw change. It does not apply pre-1.0 demotion or add the demotion note; the driver does both.
- It is read-only and deterministic: it runs from the git toplevel against the clean `HEAD`, and never tags, commits,
  pushes or writes outside temporary files.
- It is never canonical. `verify-canonical` and `governance-refresh` skip `*.local.sh`, so `keelcore/standards`' own
  hook is never copied into a project and a project's hook is never overwritten.

### The project's release-policy document

- It incorporates this policy by reference: it links to `.standards/governance/release-policy.md` and states that the
  standards policy applies in full.
- It does not restate or contradict this policy. It contains only the project's customization:
  - what the hook diffs, and why that is the project's public surface;
  - the breaking changes the hook cannot see, which call for `--force`;
  - how the hook's input is kept current (e.g. a generated schema and the check that keeps it fresh);
  - project-specific tooling and anything the hook adds to the tag message.

### Not customizable

- Tags are created only by a developer running `make create-release`; never by CI.
- `scripts/release/create-release.sh` is canonical and byte-identical in every project. Changes go to
  `keelcore/standards` first.
- The preconditions, pre-1.0 demotion, `--force` rules and the signed annotated tag.
- Tags are the only version source; no version file, no version-bump commit.

### Examples

- **keel** — the hook diffs the config field set of `pkg/config/schema.yaml` at the previous tag against `HEAD`:
  removed fields → major; added fields → minor; no change → patch. See keel's `docs/release-policy.md`.
- **keelcore/standards** — the hook reads `CHANGELOG.md` `## [Unreleased]`: any `### Removed` entry → major; else any
  `### Added` or `### Changed` entry → minor; else patch. An empty `[Unreleased]` fails.

---

## Normal Release Flow

```bash
git checkout main && git pull --ff-only
# ... merge your work ...
make create-release DRY_RUN=1   # optional preview
make create-release
```

The script will:

1. Verify you are on `main`, your branch's configured upstream is in sync, and the working tree is clean.
2. Run the project's hook and compute the next version.
3. Print the summary (the hook's findings, bump level, proposed tag subject).
4. Prompt for `y/N` approval.
5. On approval: create a signed annotated tag and push that one tag to the upstream remote.

A dry run prints the version and the full tag message without prompting, tagging or pushing, and reports failed
preconditions as warnings. CI picks up the pushed tag and runs the release pipeline (build, sign, SBOM, publish).

---

## Forcing a Specific Version

Use `--force vX.Y.Z` (`make create-release FORCE=vX.Y.Z`) to override the computed version. Only bare
`MAJOR.MINOR.PATCH` versions are accepted — pre-release extensions (`-alpha.1`) and build metadata (`+sha`) are not
supported.

### Pre-1.0 rules (current major = 0)

Per [semver.org item 9](https://semver.org/#spec-item-9), `0.y.z` is for initial development where the API is not yet
stable. Only the following targets are accepted:

- Any `0.x.y` where `0.x.y > current` — normal initial-development progression.
- Exactly `v1.0.0` — the stable API promotion per [semver.org item 10](https://semver.org/#spec-item-10), regardless of
  the hook's bump level.

Forcing `v1.1.0`, `v2.0.0`, or any other version outside this range is rejected.

### Post-1.0 rules (current major ≥ 1)

Once `1.0.0` is released the public API is stable. `--force` is restricted to exact single-step increments per
semver.org's ordering rules:

| `--force` target              | Condition                                         | Result                                                                    |
| ----------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------- |
| `cur_maj.cur_min.(cur_pat+1)` | any                                               | **Allowed** — single patch step                                           |
| `cur_maj.(cur_min+1).0`       | any                                               | **Allowed** — single minor step (e.g. changes the hook cannot see)        |
| `(cur_maj+1).0.0`             | hook reports `major` AND matches computed version | **Allowed**                                                               |
| `(cur_maj+1).0.0`             | hook does not report `major`, or no match         | **Rejected** — a major bump requires the hook to report a breaking change |
| anything else                 | —                                                 | **Rejected** — must be a single-step increment                            |

---

## What Goes in the Tag Message

The script generates a signed annotated tag with a structured message:

- **Subject line:** `{bump}: {hook subject}` (e.g. `minor: added 2 config field(s)`)
- **Body:** bump level, previous/new version, commit SHA, the hook's findings, and the `Generated-by:` trailer

The GitHub Release body can be populated directly from the tag message via `gh release create --notes-from-tag`.

---

## Emergency / Break-Glass

If a critical patch must ship and the normal flow is blocked, follow the break-glass procedure in
[`docs/break-glass.md`](../docs/break-glass.md). The bypass still requires two senior engineers and an incident record
— it does not bypass the tag-creation requirement, only the precondition checks.
