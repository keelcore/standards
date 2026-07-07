# Coding Standards

These rules govern all code edits in this project. They are non-negotiable.

**Maturity:** Required **Version:** 1.0.0 **Last Reviewed:** 2026-03-09

## Core Preservation

1. No drift — do not remove code, comments, structure, or behavior unless explicitly instructed or strictly required.
2. Semantic preservation is the default.
3. Existing comments are sticky — do not delete or rewrite unless wrong/obsolete due to the current change.
4. Reader trust is paramount — changes must be locally verifiable by a careful human reviewer.
5. Preserve error-handling strategy — no silent discards, no wrapping-depth changes.

## Commenting Rules

1. Comments explain enduring intent, invariants, contracts, architecture — not patch notes.
2. No "added this", "fixed this", "temporary workaround" style narration.
3. Comments are file-local; no broader project lore unless strictly necessary.
4. Prefer code over commentary for the obvious.
5. When updating code, update any nearby comment that would become misleading.

## Scope Control

1. All edits to existing files must be surgical — minimum necessary lines/regions/symbols.
2. No opportunistic widening — no drive-by refactors, renames, formatting sweeps, dead-code cleanup.
3. Do not introduce dead code — no unreachable branches, unused variables/imports, orphaned helpers.
4. Do not reflow stable text gratuitously.
5. Preserve surrounding code shape.
6. Minimize diff surface area; correctness wins over minimalism when they conflict.

## Consistency and Reviewability

1. Human reviewability outranks aesthetic optimization.
2. Match local conventions: repo/module > file-local > language style guide.
3. Avoid sweeping rewrites.
4. Maintain interface stability — no silent signature/flag/config-key changes.
5. When practical, preserve backward compatibility; do not silently drop old forms.
6. Preserve blame usefulness — keep unchanged lines untouched.

## Refactoring Rules

1. Refactoring is opt-in, not ambient.
2. Required refactors must be local.
3. Do not bundle unrelated improvements.
4. Prefer extension over churn.

## File Editing Discipline

1. Preserve untouched regions exactly.
2. Do not reorder imports, declarations, functions, keys, or fields unless required.
3. Do not rename symbols for taste.
4. Do not change comments/docstrings/whitespace outside the affected area.
5. Never leave a file in a partially migrated state.

## New File Discipline

1. Follow naming, package structure, header conventions of adjacent files.
2. Creating a new file requires explicit justification; prefer extending existing files.
3. Test files may use longer functions, explicit repetition, table-driven patterns — do not compress.

## Style

1. Prefer boring, conventional, long-lived patterns over novelty.
2. Follow language style guide unless local style clearly overrides.
3. Conservative house style: readability, portability, diff minimization, explicitness, reviewer clarity.
4. Style must be consistent within the file and stable across future edits.

## Security

1. No hardcoded credentials, tokens, private keys, disabled TLS verification, open CORS, permissive file modes. Note
   existing violations and raise them rather than propagating them.

## Documentation

1. When observable behavior/flags/config/API/errors change, note that external docs may need updating.

## Formatting and Linting Automation

1. Format and lint via project scripts, not ad-hoc commands.
2. Propose `scripts/format.sh` and `scripts/lint.sh` if they do not exist.
3. Do not embed formatter/linter invocations in YAML or Makefiles when a script can be the entry point.

## Git Hook Integration

1. Pre-commit hook calls a single stable entry point: `scripts/git_precommit.sh`.
2. `scripts/git_precommit.sh` invokes format + lint scripts; no logic duplicated in the hook itself.

## Change Justification

1. Every non-trivial change must be justifiable as necessary.
2. No speculative fixes.
3. No silent cleanup of unconventional-but-correct code.
4. Preserve intent over stylistic purity.

## Completeness and Consistency

1. Do not leave referenced functions/variables/imports/code paths broken.
2. No partial renames, partial signature migrations, inconsistent call-site updates.
3. Changed code must remain internally consistent with the rest of the file.
4. Prefer a complete narrow fix over an ambitious broad rewrite.

## Default Operating Principle

1. Treat every edit as a constrained maintenance operation, not a redesign opportunity.
2. Ideal change: minimal, correct, legible, locally consistent, unsurprising.

## Concurrency and Shared-State Safety

1. Do not remove synchronization primitives or introduce unprotected shared state.
2. Do not introduce goroutines/threads/async into previously synchronous code paths.
3. Do not move code across concurrency boundaries without preserving ordering and safety.

## Type and Contract Safety

1. Do not widen specific types to any/interface{}/generic containers.
2. No unsafe casts, reflection-driven access, or dynamic fallbacks where typed alternatives exist.
3. Do not remove type checks, assertions, validation, or boundary contracts without equal replacement.

## Ambiguity Control

1. When ambiguous, prefer the narrowest conservative interpretation consistent with literal text and intent.
2. Seek clarification only when conservative interpretation produces broken, incomplete, or unsafe output.

## Complexity Preservation

1. Do not introduce worse asymptotic complexity where a better one existed.
2. Do not replace indexed/cached/streaming/incremental behavior with full scans or redundant allocation.

## Locale and Reproducibility

1. Builds, tests, and tooling MUST be reproducible independent of the developer's or CI runner's
   locale. Never depend on an inherited `LANG`/`LC_*` for program behavior.
2. Any locale-sensitive operation — collation/sort order, numeric or date formatting, case-folding —
   MUST pin an explicit, deterministic locale (`LC_ALL=C`, or an equivalent language-native
   invariant) rather than rely on the ambient default.
3. Pin at the outermost boundary that covers all subprocesses (e.g. the build entrypoint exports
   `LC_ALL=C`) so that tools you do not own inherit the deterministic locale too.
4. Where a locale dependency is load-bearing, add a test that runs the path under a hostile `LC_*`
   and asserts the invariant holds. Language-specific mechanics live in the per-language standards
   (e.g. bash.md, "Locale Determinism").

## Source File Trailing Newlines

1. Every text source file (`.go`, `.sh`, `.md`, `.yml`, `.yaml`, `.toml`, `.json`, `.gitignore`, `.gitattributes`) MUST
   end with a single trailing newline character.
2. Verify and fix trailing newlines before handing off any file edits.
3. Adding a new text-format type to the repo requires updating `scripts/lint/newlines.sh` and the pre-commit hook in the
   same commit.

## Go Module Version Format

1. The `go` directive in `go.mod` MUST use the two-component form: `go 1.25` — never `go 1.25.0`.
2. After every `go mod tidy` or `go get`, verify the `go` directive and strip any trailing `.0`.

## Static Analysis Suppression

1. The standalone `staticcheck` binary does NOT respect `//nolint:staticcheck` directives. Use
   `//lint:ignore SA1019 <reason>` instead.
2. Place the `//lint:ignore` directive on its own line immediately above the flagged statement — inline (end-of-line)
   placement may be silently ignored.

## Program Entry Points

1. `main` (and any program entry point) must be KISS: orchestration and wiring only.
2. No default behaviors, business logic, or configuration in `main` — those belong in the library.
3. A correct `main` is ~15 lines: parse flags, call library, handle exit.
