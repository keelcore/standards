# AI Model Conduct Standards

These rules govern the behavior of AI coding assistants (Claude, Copilot, Cursor, or equivalent)
when working in projects under this governance. They are non-negotiable and take precedence over
any model-default behavior.

**Maturity:** Required
**Version:** 1.0.0
**Last Reviewed:** 2026-03-14

## Commit Attribution

- Do NOT add `Co-Authored-By`, `Generated-by`, or any AI attribution trailer to commit messages.
- Commit messages contain only the subject, optional body, and the required DCO `Signed-off-by`
  trailer. No AI branding.

## Test File Protection

- Do NOT modify test files without explicit prior authorization from the developer.
- When a test fails, find and fix the root cause in production code. Do not adjust the test to
  make it pass.
- Exceptions (adding a new test, fixing a test bug, tracking an intentional contract change)
  require explicit approval in the conversation before any edit is made.

## Test Suite Execution

- Run `make test` (or `make unit-test` at minimum) before declaring any code change complete.
- Do not hand off code without verifying the test suite passes.
- If tests cannot be run (environment constraint), state this explicitly and enumerate what was
  not validated.

## Entry Point Files Are Pinned

- `main.go` (and any program entry point file) is pinned — do not edit it without explicit
  developer consent in the current conversation.
- Entry points are considered high-blast-radius: a silent change to `main` can alter startup
  behavior, flag defaults, or initialization order in ways that are hard to review.

## Bash Script Delivery

- When writing or editing a bash script, always deliver the complete script.
- Never deliver a diff, patch, or partial snippet of a bash script.
- Rationale: partial bash edits are error-prone; the complete script is reviewable as a unit.

## Governance Supremacy

- Project governance documents (this repo's `governance/` tree) override any model default or
  prior training behavior.
- When a governance rule conflicts with a model default (e.g., adding attribution, adding
  speculative features, cleaning up untouched code), governance wins without exception.
- If a governance rule is ambiguous, ask for clarification rather than applying a default.

## Scope Discipline

- Do not perform unrequested cleanup, refactoring, or improvements in files adjacent to the
  current change.
- Do not add docstrings, comments, or type annotations to code not directly modified.
- Do not add error handling, fallbacks, or validation for scenarios that cannot occur.
- Surgical edits only: the smallest correct change that satisfies the request.

## Memory and Governance Relationship

- Model memory (session-local or persisted) is subordinate to governance.
- If a memory contradicts governance, flag the conflict to the developer; do not silently pick
  one over the other.
- Governance is the source of truth; memory captures working context and in-flight decisions.
