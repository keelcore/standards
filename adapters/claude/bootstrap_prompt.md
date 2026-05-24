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

The acceptance gate is `scripts/ci/audit-make-targets.sh` — authored during bootstrap
per [../../governance/ci.md](../../governance/ci.md), then invoked as `make audit`.

## Human-in-the-loop contract

Claude stages; the human commits. The prompt forbids `git commit`, `git push`, and
all destructive git operations. Each step ends with "stage and pause for review,"
giving the human a clean diff to inspect before committing.

## The prompt

```text
Bootstrap this repo to keelcore engineering standards. Work in this order. After each
step, `git add` the new files and STOP for human review + commit before proceeding.
You may stage; you may not commit. The human owns every commit.

1. Add the standards submodule:
     git submodule add git@github.com:keelcore/standards .standards
     git submodule update --init --recursive
   Then read .standards/governance/{coding,ci,testing,bash}.md end-to-end. These are
   authoritative — every later step must satisfy them. Stage and pause for review.

2. Create CLAUDE.md at repo root that references the governance docs by relative path
   (.standards/governance/*.md) and @-includes a .local-claude.md for project-specific
   guidance. Mirror the structure of .standards/adapters/claude/CLAUDE.md.
   Stage and pause for review.

3. Bootstrap scripts/ per governance/coding.md and governance/ci.md:
     scripts/format.sh, scripts/lint.sh, scripts/git_precommit.sh
     scripts/lib/paths.sh
     scripts/lint/{markdown.sh,newlines.sh,shellcheck.sh}
     scripts/ci/{audit-make-targets.sh,dco-check.sh,secret-scan.sh,
                 setup-shellcheck.sh,setup-markdownlint.sh,setup-syft.sh,
                 verify-canonical-scripts.sh}
     scripts/check/{adr-metadata.sh,governance-metadata.sh,rfc-metadata.sh}
     scripts/test/{coverage.sh,coverage-delta.sh}
   All scripts: bash strict mode, shellcheck-clean, end with \n, executable.
   Stage and pause for review.

4. Bootstrap Makefile per governance/ci.md "Universal Canonical Makefile Targets":
   one target per script entrypoint, no inline bash/sh/bats/go/chmod in recipes,
   every scripts/**/*.sh (except scripts/lib/) referenced by exactly one target.
   Include `setup-bats`, `unit-test`, `integration-test`, `audit`, `coverage`,
   `ci-coverage-delta`, `ci-secret-scan`, `ci-dco`, `lint-newlines`, plus format/lint.
   Stage and pause for review.

5. Bootstrap BATS per governance/testing.md:
     tests/canonical/smoke.bats
     tests/integrity.bats   (runs against the built artifact, not source)
     tests/fixtures/        (static inputs only; no generated artifacts committed)
   `make setup-bats` installs the framework; `make integration-test` runs BATS.
   Stage and pause for review.

6. Wire pre-commit: a single hook calling scripts/git_precommit.sh, which invokes
   format + lint scripts. No logic duplicated in the hook. Stage and pause for review.

7. Add .gitleaks.toml, .markdownlint.json, .prettierrc to match keelcore defaults.
   Stage and pause for review.

Acceptance — all must pass before reporting done (run these yourself, do not commit):
  - `make audit`              (scripts/ci/audit-make-targets.sh — the compliance gate)
  - `make lint`
  - `make unit-test`
  - `make integration-test`
  - `git submodule status` shows .standards clean
  - Every scripts/**/*.sh appears in exactly one Makefile recipe

Rules:
  - NEVER run `git commit`, `git commit --amend`, `git push`, `git reset --hard`,
    `git checkout --`, `git clean -f`, or any destructive git operation. The human
    reviews and commits each step.
  - `git add <specific paths>` is allowed; `git add -A` / `git add .` is not.
  - Test each script against realistic input before reporting a step ready — shellcheck-
    clean is necessary but not sufficient.
  - Do NOT use Python anywhere.
```

## Step-order rationale

Submodule first so governance docs become readable. Then scripts (Makefile recipes
need them to exist). Then `Makefile`. Then BATS. Then pre-commit. Then ancillary
config. Acceptance is a self-audit (`make audit`) plus runs of the canonical layer
targets.
