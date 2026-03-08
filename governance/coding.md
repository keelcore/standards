# Coding Standards

These rules govern all code edits in this project. They are non-negotiable.

**Maturity:** Required
**Version:** 1.0.0
**Last Reviewed:** 2026-03-09

## Core Preservation

1. No drift — do not remove code, comments, structure, or behavior unless explicitly instructed or strictly required.
2. Semantic preservation is the default.
3. Existing comments are sticky — do not delete or rewrite unless wrong/obsolete due to the current change.
4. Reader trust is paramount — changes must be locally verifiable by a careful human reviewer.
5. Preserve error-handling strategy — no silent discards, no wrapping-depth changes.

## Commenting Rules

6. Comments explain enduring intent, invariants, contracts, architecture — not patch notes.
7. No "added this", "fixed this", "temporary workaround" style narration.
8. Comments are file-local; no broader project lore unless strictly necessary.
9. Prefer code over commentary for the obvious.
10. When updating code, update any nearby comment that would become misleading.

## Scope Control

11. All edits to existing files must be surgical — minimum necessary lines/regions/symbols.
12. No opportunistic widening — no drive-by refactors, renames, formatting sweeps, dead-code cleanup.
13. Do not introduce dead code — no unreachable branches, unused variables/imports, orphaned helpers.
14. Do not reflow stable text gratuitously.
15. Preserve surrounding code shape.
16. Minimize diff surface area; correctness wins over minimalism when they conflict.

## Consistency and Reviewability

17. Human reviewability outranks aesthetic optimization.
18. Match local conventions: repo/module > file-local > language style guide.
19. Avoid sweeping rewrites.
20. Maintain interface stability — no silent signature/flag/config-key changes.
21. When practical, preserve backward compatibility; do not silently drop old forms.
22. Preserve blame usefulness — keep unchanged lines untouched.

## Refactoring Rules

23. Refactoring is opt-in, not ambient.
24. Required refactors must be local.
25. Do not bundle unrelated improvements.
26. Prefer extension over churn.

## File Editing Discipline

27. Preserve untouched regions exactly.
28. Do not reorder imports, declarations, functions, keys, or fields unless required.
29. Do not rename symbols for taste.
30. Do not change comments/docstrings/whitespace outside the affected area.
31. Never leave a file in a partially migrated state.

## New File Discipline

32. Follow naming, package structure, header conventions of adjacent files.
33. Creating a new file requires explicit justification; prefer extending existing files.
34. Test files may use longer functions, explicit repetition, table-driven patterns — do not compress.

## Style

35. Prefer boring, conventional, long-lived patterns over novelty.
36. Follow language style guide unless local style clearly overrides.
37. Conservative house style: readability, portability, diff minimization, explicitness, reviewer clarity.
38. Style must be consistent within the file and stable across future edits.

## Security

39. No hardcoded credentials, tokens, private keys, disabled TLS verification, open CORS, permissive file modes.
    Note existing violations and raise them rather than propagating them.

## Documentation

40. When observable behavior/flags/config/API/errors change, note that external docs may need updating.

## Formatting and Linting Automation

41. Format and lint via project scripts, not ad-hoc commands.
42. Propose `scripts/format.sh` and `scripts/lint.sh` if they do not exist.
43. Do not embed formatter/linter invocations in YAML or Makefiles when a script can be the entry point.

## Git Hook Integration

44. Pre-commit hook calls a single stable entry point: `scripts/git_precommit.sh`.
45. `scripts/git_precommit.sh` invokes format + lint scripts; no logic duplicated in the hook itself.

## Change Justification

46. Every non-trivial change must be justifiable as necessary.
47. No speculative fixes.
48. No silent cleanup of unconventional-but-correct code.
49. Preserve intent over stylistic purity.

## Completeness and Consistency

50. Do not leave referenced functions/variables/imports/code paths broken.
51. No partial renames, partial signature migrations, inconsistent call-site updates.
52. Changed code must remain internally consistent with the rest of the file.
53. Prefer a complete narrow fix over an ambitious broad rewrite.

## Default Operating Principle

54. Treat every edit as a constrained maintenance operation, not a redesign opportunity.
55. Ideal change: minimal, correct, legible, locally consistent, unsurprising.

## Concurrency and Shared-State Safety

56. Do not remove synchronization primitives or introduce unprotected shared state.
57. Do not introduce goroutines/threads/async into previously synchronous code paths.
58. Do not move code across concurrency boundaries without preserving ordering and safety.

## Type and Contract Safety

59. Do not widen specific types to any/interface{}/generic containers.
60. No unsafe casts, reflection-driven access, or dynamic fallbacks where typed alternatives exist.
61. Do not remove type checks, assertions, validation, or boundary contracts without equal replacement.

## Ambiguity Control

62. When ambiguous, prefer the narrowest conservative interpretation consistent with literal text and intent.
63. Seek clarification only when conservative interpretation produces broken, incomplete, or unsafe output.

## Complexity Preservation

64. Do not introduce worse asymptotic complexity where a better one existed.
65. Do not replace indexed/cached/streaming/incremental behavior with full scans or redundant allocation.
