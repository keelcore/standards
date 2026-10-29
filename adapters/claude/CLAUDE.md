# Engineering Standards

Apply the following standards in full for all work in this repository.

## Coding Standards

See [.standards/governance/coding.md](.standards/governance/coding.md).

## CI Standards

See [.standards/governance/ci.md](.standards/governance/ci.md).

## Makefile `.PHONY` Declarations

Declare exactly one target per `.PHONY` line — `.PHONY: build`, then `.PHONY: lint` on the next line. Never a
space-separated or backslash-continued list. Make aggregates repeated `.PHONY:` lines on its own, and one name per line
keeps diffs and blame to the single target that changed. Adding a target adds its own `.PHONY: <target>` line.

## Testing Standards

See [.standards/governance/testing.md](.standards/governance/testing.md).

## Bash Standards

See [.standards/governance/bash.md](.standards/governance/bash.md).

## Platform Architecture Standards

See [.standards/governance/platform.md](.standards/governance/platform.md).

## Observability Standards

See [.standards/governance/observability.md](.standards/governance/observability.md).

## Security Standards

See [.standards/governance/security.md](.standards/governance/security.md).

## Runtime and Orchestration Standards

See [.standards/governance/runtime.md](.standards/governance/runtime.md).

## API Management Standards

See [.standards/governance/api-management.md](.standards/governance/api-management.md).

## AI Conduct Standards

See [.standards/governance/ai/conduct.md](.standards/governance/ai/conduct.md).

## Bootstrap Prompt

To stand up a new keelcore-standards repository (submodule, canonical `scripts/`, `Makefile`, BATS, pre-commit), use the
paste-ready prompt at [.standards/adapters/claude/bootstrap_prompt.md](.standards/adapters/claude/bootstrap_prompt.md).
It encodes the human-in-the-loop contract: Claude stages, the human commits.

## Project-Specific Guidance

Project-local conventions, build instructions, and architecture notes live in [.local-claude.md](.local-claude.md).

@.local-claude.md
