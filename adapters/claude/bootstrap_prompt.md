# Bootstrap Prompt — Claude Code

A self-contained prompt you can paste into a fresh Claude Code session to bring a new repository up to keelcore
engineering standards: submodule, governance-mandated `scripts/`, canonical `Makefile`, BATS test harness, configs, and
pre-commit wiring.

## What this prompt enforces

The prompt makes Claude actualize the requirements already documented in:

- [../../governance/coding.md](../../governance/coding.md) — canonical script entrypoints, pre-commit hook shape, no
  formatter/linter logic embedded in YAML or `Makefile` recipes.
- [../../governance/ci.md](../../governance/ci.md) — "Makefile Entrypoints" and "Universal Canonical Makefile Targets".
  The Makefile is the single dev-facing interface; every `scripts/**/*.sh` (except `scripts/lib/`) MUST be referenced by
  exactly one Makefile target. Every Makefile target has AT MOST one active recipe line, which MUST invoke a single
  `scripts/**/*.sh` script (Rule 4).
- [../../governance/testing.md](../../governance/testing.md) — fixed test layer names + Makefile targets,
  `tests/integrity.bats`, `tests/fixtures/`, BATS as the integration harness.
- [../../governance/bash.md](../../governance/bash.md) — bash strict mode, portability, structure, logging.
- [CLAUDE.md](CLAUDE.md) — the adapter Claude reads on session start; the bootstrap symlinks it as the consumer's
  `CLAUDE.md`.

The acceptance gate is `scripts/ci/audit-make-targets.sh` — vendored by `bootstrap-standards.sh`, invoked as
`make audit`.

## Human-in-the-loop contract

Claude stages; the human commits. The prompt forbids `git commit`, `git push`, and all destructive git operations.

## What bootstrap-standards.sh does for you

A single invocation of `bash .standards/scripts/bootstrap-standards.sh` materializes everything below — no file
authoring required:

1. **Canonical scripts** (overwritten to guarantee byte-identical with .standards):
   - `scripts/ci/{audit-make-targets,dco-check,pr-policy,secret-scan,setup-bats, setup-markdownlint,setup-shellcheck,setup-syft,verify-canonical-scripts}.sh`
   - `scripts/check/{adr-metadata,governance-metadata,rfc-metadata}.sh`
   - `scripts/{format,lint,git_precommit,install-hooks,check-legal-drift}.sh`
   - `scripts/lib/paths.sh`
   - `scripts/lint/{markdown,newlines,shellcheck}.sh`
   - `scripts/test/{coverage,coverage-delta}.sh`
2. **Starter templates** (created ONLY if the target file doesn't exist; never overwrites operator customizations on
   re-run):
   - `Makefile` — material copy from `.standards/templates/Makefile` (which is also the source for `.standards/Makefile`
     via symlink — single source of truth). Contains all canonical universal targets wired to `bash scripts/X.sh`, plus
     a few standards-repo-specific targets the operator can prune (release-go, release-npm, release-pypi, verify-go,
     bootstrap-standards).
   - `tests/canonical/smoke.bats` — harness sanity, project-agnostic
   - `tests/integrity.bats` — stub with TODO markers for your built artifact
   - `tests/fixtures/.gitkeep` — testing.md fixture-dir placeholder
   - `.gitleaks.toml` — extends gitleaks defaults; sensible allowlist
   - `.markdownlintignore` — excludes `.standards/`, build outputs, scratch
   - `.prettierrc` — keelcore defaults (printWidth 100, lf, etc.)
   - `.local-claude.md` — project-specific guidance stub

   Per ci.md Rule 4: every Makefile target has at most ONE active recipe line, which MUST invoke a single
   `scripts/**/*.sh` script. The templated Makefile already obeys this — keep it that way as you customize.

3. **Repo config**:
   - `.markdownlint.json` — copied from `.standards/.markdownlint.json`
4. **AI adapters**:
   - `CLAUDE.md` — symlinked to `.standards/adapters/claude/CLAUDE.md`
     - Non-greenfield: existing `CLAUDE.md` is first moved to `.local-claude.md` (the canonical adapter
       `@.local-claude.md`-includes it, so content survives)
   - `.github/copilot-instructions.md` — symlinked
   - `.cursor/rules/*.mdc` — copied and path-adjusted
5. **Tooling installation** (idempotent; no-op if already installed):
   - shellcheck, markdownlint-cli, syft
6. **Pre-commit hook**:
   - `.git/hooks/pre-commit → ../../scripts/git_precommit.sh` (via install-hooks.sh)

## Non-greenfield repos

The bootstrap is safe to run on a repo that already has a `CLAUDE.md`, `Makefile`, configs, or BATS tests:

- **CLAUDE.md**: existing content migrated to `.local-claude.md` automatically; the symlinked canonical adapter
  re-includes it. Inspect the resulting `.local-claude.md` and prune anything now duplicated by the canonical adapter.
- **Makefile**: existing Makefile is PRESERVED verbatim — the template is NOT copied over it. Operator merges canonical
  targets from `.standards/templates/Makefile` (or equivalently `.standards/Makefile`, which is a symlink to the same
  file) into the existing Makefile manually, preserving every project-specific target.
- **Configs / BATS / .local-claude.md**: existing files are PRESERVED verbatim. Bootstrap doesn't touch them.
- **Canonical scripts under `scripts/`**: always overwritten to maintain byte-identical guarantee. Project-specific
  scripts alongside them (`scripts/fetch-data.sh`, `scripts/build.sh`, etc.) are untouched.

## The prompt

```text
Bootstrap this repo to keelcore engineering standards. Work in this order. After each
step, `git add` the new files and STOP for human review + commit before proceeding.
You may stage; you may not commit. The human owns every commit.

1. Add the standards submodule (skip if .standards/ already exists):
     git submodule add git@github.com:keelcore/standards .standards
     git submodule update --init --recursive
   Then read .standards/governance/{coding,ci,testing,bash}.md end-to-end. These are
   authoritative — every later step must satisfy them. Stage and pause for review.

2. Run the canonical bootstrap:
     bash .standards/scripts/bootstrap-standards.sh
   This materializes every canonical script (scripts/**/*.sh), copies starter
   templates (Makefile, tests/canonical/smoke.bats, tests/integrity.bats,
   tests/fixtures/, .gitleaks.toml, .markdownlintignore, .prettierrc,
   .local-claude.md) ONLY if their target doesn't already exist, installs tooling
   (shellcheck, markdownlint, syft), copies .markdownlint.json, symlinks the AI
   adapters (CLAUDE.md, .github/copilot-instructions.md, .cursor/rules/*.mdc),
   and wires the pre-commit hook (.git/hooks/pre-commit).
   Idempotent: safe to re-run. Templates are NEVER overwritten on subsequent runs;
   canonical scripts ARE always overwritten to maintain byte-identical guarantee.
   Stage and pause for review.

3. Customize the templates that bootstrap created (or merged on non-greenfield):
   - Makefile (greenfield): the template was copied verbatim. Prune the
     standards-repo-specific targets your project doesn't need (release-go,
     release-npm, release-pypi, verify-go, bootstrap-standards, lint-md).
     Add language-specific recipes for `build`, `release`, `test`, `unit-test`,
     `integration-test`, `clean` — each wrapped in `scripts/<name>.sh` per
     Rule 4 (one active recipe line, calls one scripts/**/*.sh).
   - Makefile (non-greenfield): bootstrap left your existing Makefile alone.
     Merge canonical-target definitions from `.standards/templates/Makefile`
     into your existing file alongside the project's own targets. Do NOT
     replace project-specific targets. Do NOT remove existing @echo lines.
   - tests/integrity.bats: update the BIN path to point at your built artifact;
     replace example assertions with smoke checks of your binary's surface.
   - .local-claude.md: prune the template stub and add project-specific guidance
     (workspace shape, build instructions, test layout, commit policy).
   - .gitleaks.toml, .markdownlintignore: extend allowlist/ignore patterns with
     repo-specific paths.
   Stage and pause for review.

Acceptance — all must pass before reporting done (run these yourself, do not commit):
  - `make audit`              (scripts/ci/audit-make-targets.sh — the compliance gate)
  - `make lint`
  - `make unit-test`
  - `make integration-test`
  - `git submodule status` shows .standards clean
  - `bash .standards/scripts/ci/verify-canonical-scripts.sh .`
    (all canonical scripts byte-identical with .standards)
  - Every scripts/**/*.sh appears in exactly one Makefile recipe
  - Pre-existing project content lint failures (e.g. markdown table-style errors in
    existing docs) are FLAGGED to the human, not silently fixed and not silently
    suppressed — the human decides whether to fix docs or relax rules.

Rules:
  - NEVER run `git commit`, `git commit --amend`, `git push`, `git reset --hard`,
    `git checkout --`, `git clean -f`, or any destructive git operation. The human
    reviews and commits each step.
  - `git add <specific paths>` is allowed; `git add -A` / `git add .` is not.
  - On non-greenfield repos: MERGE the Makefile, do not replace. Preserve every
    project-specific target.
  - Do NOT remove @echo lines from existing Makefile recipes — they are
    informational and not the same as substantive commands.
  - Do NOT use Python anywhere.
```

## Step-order rationale

Submodule first so governance docs become readable. Then `bootstrap-standards.sh` materializes scripts, templates,
configs, adapters, and the pre-commit hook in the correct order. Then operator customizes per project (mainly: filling
in the Makefile's project-specific targets, pointing integrity.bats at the built artifact). Acceptance is `make audit`
plus runs of the canonical layer targets.

The bootstrap script is idempotent and self-sufficient — no Claude file authoring required for steps 2 and 3
(customization only touches files the operator chose to edit; the prompt does not need to generate file content from
scratch).
