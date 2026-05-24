# Bootstrap Prompt — Claude Code

A self-contained prompt you can paste into a fresh Claude Code session to bring a new
repository up to keelcore engineering standards: submodule, governance-mandated
`scripts/`, canonical `Makefile`, BATS test harness, and pre-commit wiring.

## What this prompt enforces

The prompt makes Claude actualize the requirements already documented in:

- [../../governance/coding.md](../../governance/coding.md) — canonical script entrypoints
  (`scripts/format.sh`, `scripts/lint.sh`, `scripts/git_precommit.sh`), pre-commit hook
  shape, no formatter/linter logic embedded in YAML or `Makefile` recipes.
- [../../governance/ci.md](../../governance/ci.md) — "Makefile Entrypoints" and
  "Universal Canonical Makefile Targets". The Makefile is the single dev-facing
  interface; every `scripts/**/*.sh` (except `scripts/lib/`) must be referenced by
  exactly one Makefile target. Includes `make audit` (the compliance auditor),
  `make setup-bats`, `make ci-secret-scan`, `make ci-dco`, etc.
- [../../governance/testing.md](../../governance/testing.md) — fixed test layer
  names + Makefile targets, `tests/integrity.bats`, `tests/fixtures/`, BATS as the
  integration harness.
- [../../governance/bash.md](../../governance/bash.md) — bash strict mode,
  portability, structure, logging.
- [CLAUDE.md](CLAUDE.md) — the adapter Claude reads on session start; the bootstrap
  prompt creates the consumer-repo `CLAUDE.md` that mirrors it.

The acceptance gate is `scripts/ci/audit-make-targets.sh` — vendored by
`bootstrap-standards.sh`, then invoked as `make audit`.

## Human-in-the-loop contract

Claude stages; the human commits. The prompt forbids `git commit`, `git push`, and
all destructive git operations. Each step ends with "stage and pause for review,"
giving the human a clean diff to inspect before committing.

## Non-greenfield repos

The same prompt works on a repo that already has a `CLAUDE.md`, `Makefile`, or
`scripts/` tree. Two rules govern how Claude handles existing artifacts:

1. **CLAUDE.md migration.** If `CLAUDE.md` already exists and is not the canonical
   symlink, `bootstrap-standards.sh` moves it to `.local-claude.md` (where the
   canonical adapter's `@.local-claude.md` include picks it up) before symlinking
   the adapter into place. Prior project guidance survives intact. If
   `.local-claude.md` also already exists, bootstrap warns and leaves `CLAUDE.md`
   untouched — the operator reconciles manually.
2. **Makefile merge-not-overwrite.** Existing Makefile targets (cargo run-targets,
   data-fetch helpers, project-specific orchestration) are preserved verbatim. The
   prompt instructs Claude to **add** the canonical universal targets alongside
   existing recipes, never to replace project-specific ones. The `make audit` gate
   only checks that the canonical targets exist and that every `scripts/**/*.sh`
   appears in exactly one recipe — it does not police what else is in the file.

For all other artifacts (config files, BATS scaffolding, hooks), bootstrap is
safe to re-run: canonical scripts overwrite themselves by `cp`; project-specific
scripts living alongside them are untouched.

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

2. CLAUDE.md and .local-claude.md.
   - Greenfield: bootstrap-standards.sh (step 3) will symlink CLAUDE.md to
     .standards/adapters/claude/CLAUDE.md. Create .local-claude.md with project-
     specific guidance (build instructions, workspace shape, test layout,
     commit policy reminders).
   - Non-greenfield: if a CLAUDE.md already exists, bootstrap-standards.sh moves it
     to .local-claude.md so its content survives, then symlinks the canonical
     adapter. The adapter's @.local-claude.md include re-loads the moved content.
     Inspect the resulting .local-claude.md and prune anything now duplicated by
     the canonical adapter.
   Stage and pause for review.

3. Run the canonical bootstrap:
     bash .standards/scripts/bootstrap-standards.sh
   This copies every canonical script into scripts/ (ci/, check/, lint/, test/, lib/,
   plus top-level format.sh, lint.sh, git_precommit.sh, check-legal-drift.sh),
   copies .markdownlint.json into the repo root, symlinks the AI adapters
   (CLAUDE.md, .github/copilot-instructions.md, .cursor/rules/*.mdc), and chmods
   the script tree.
   Bootstrap is idempotent and safe to re-run. It never overwrites the Makefile.
   Verify the script tree afterward; the resulting layout MUST match:
     scripts/format.sh, scripts/lint.sh, scripts/git_precommit.sh
     scripts/check-legal-drift.sh
     scripts/lib/paths.sh
     scripts/lint/{markdown.sh,newlines.sh,shellcheck.sh}
     scripts/ci/{audit-make-targets.sh,dco-check.sh,pr-policy.sh,secret-scan.sh,
                 setup-shellcheck.sh,setup-markdownlint.sh,setup-syft.sh,
                 verify-canonical-scripts.sh}
     scripts/check/{adr-metadata.sh,governance-metadata.sh,rfc-metadata.sh}
     scripts/test/{coverage.sh,coverage-delta.sh}
   All scripts: bash strict mode, shellcheck-clean, end with \n, executable.
   Stage and pause for review.

4. Makefile per governance/ci.md "Universal Canonical Makefile Targets".
   - Greenfield: author the Makefile fresh.
   - Non-greenfield: MERGE the canonical targets into the existing Makefile.
     Preserve every project-specific target (cargo run-*, data-fetch helpers,
     orchestration). Add canonical targets alongside; do not replace.
   Required canonical targets:
     build, lint, test, unit-test, integration-test, clean, audit, coverage,
     ci-coverage-delta, ci-pr-policy, ci-secret-scan, ci-dco, lint-newlines,
     check-legal-drift, setup-bats, install-hooks, format
   Constraints (from ci.md):
     - No inline bash/sh/bats/go/chmod in recipes; recipes invoke scripts only.
     - Every scripts/**/*.sh (except scripts/lib/) referenced by exactly one target.
     - The make audit auditor enforces these invariants.
   Stage and pause for review.

5. BATS per governance/testing.md:
     tests/canonical/smoke.bats        — basic harness sanity (skip on missing tools)
     tests/integrity.bats              — runs against the built artifact, not source
     tests/fixtures/                   — static inputs only; no generated artifacts committed
   `make setup-bats` installs the framework (no-op if bats is already on PATH);
   `make integration-test` runs BATS. Cohabit with existing language-native tests
   (cargo tests under tests/*.rs, go tests under tests/, etc.) — BATS and those
   coexist by file extension.
   Stage and pause for review.

6. Wire pre-commit: install scripts/git_precommit.sh as the pre-commit hook.
   The existing install-hooks Makefile target should symlink it into .git/hooks/.
   The hook calls scripts/format.sh and scripts/lint.sh; no logic is duplicated
   in the hook. Stage and pause for review.

7. Configs:
     .markdownlint.json    — copied from .standards by bootstrap-standards.sh
     .markdownlintignore   — author per-project (exclude .standards/, target/,
                             node_modules/, build/scratch dirs)
     .gitleaks.toml        — NOT vendored; author from keelcore defaults
                             (start from gitleaks' built-in rules, allow-list
                             project-specific safe patterns)
     .prettierrc           — NOT vendored; author from keelcore defaults if the
                             project uses prettier; skip if not applicable
   Stage and pause for review.

Acceptance — all must pass before reporting done (run these yourself, do not commit):
  - `make audit`              (scripts/ci/audit-make-targets.sh — the compliance gate)
  - `make lint`
  - `make unit-test`
  - `make integration-test`
  - `git submodule status` shows .standards clean
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
    project-specific target. The CLAUDE.md migration is handled by
    bootstrap-standards.sh; do not pre-empt it manually.
  - Test each script against realistic input before reporting a step ready —
    shellcheck-clean is necessary but not sufficient.
  - Do NOT use Python anywhere.
```

## Step-order rationale

Submodule first so governance docs become readable. CLAUDE.md / `.local-claude.md`
next so future steps can reference project conventions. Then `bootstrap-standards.sh`
to materialize the script tree (Makefile recipes need scripts to exist). Then
`Makefile`. Then BATS. Then pre-commit. Then ancillary config. Acceptance is a
self-audit (`make audit`) plus runs of the canonical layer targets.

`bootstrap-standards.sh` is the canonical source of script content; it is safe to
re-run and handles the non-greenfield CLAUDE.md migration automatically. Hand-
listing scripts in the prompt has been replaced by a single invocation of the
bootstrap script.
