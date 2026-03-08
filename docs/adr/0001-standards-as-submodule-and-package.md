# ADR-0001: Standards Distributed as Both Submodule and Language Package

**Date:** 2026-03-09
**Status:** Accepted

## Context

Engineering standards (coding, CI, bash) must be shared across multiple repositories and consumed by
multiple AI coding tools (Claude, Cursor, Copilot) and human contributors. The standards must have a
single source of truth, be versionable, and be consumable without tool-specific friction.

Two distribution mechanisms were considered independently. A decision was needed on whether to pick one
or support both.

## Decision

Standards are distributed from a single repository (`github.com/keelcore/standards`) via two mechanisms:

1. **Git submodule** (default, language-agnostic) — any repo can pin a specific commit of the standards
   via `git submodule add`. Works for all language ecosystems without additional tooling.

2. **Language package** (Go: `go get`, Node: `npm install`, Python: `pip install`) — language-native
   consumption that integrates with existing dependency management, lockfiles, and vendoring. Go projects
   use `//go:embed` + a `materialize` command to extract files at `go generate` time.

Both mechanisms consume the same `governance/` directory. The package manifests (`go.mod`, `package.json`,
`pyproject.toml`) are thin wrappers that do not duplicate governance content.

## Consequences

**Positive:**

- Single source of truth for all governance content.
- Version pinning is explicit and auditable regardless of consumption mechanism.
- Language-native teams get their familiar workflow; polyglot teams use submodule.
- A single tag in the standards repo triggers all package ecosystem publications via CI.

**Negative:**

- Publishing to three package ecosystems requires CI maintenance.
- Submodule UX remains awkward for engineers unfamiliar with it.
- Consumer repos must choose and document their consumption mechanism.

## Alternatives Considered

- **Submodule only:** Simplest, but no package manager integration. Rejected because Go projects benefit
  from vendoring governance alongside code dependencies.
- **Package only:** Language-scoped. Rejected because it excludes polyglot repos and non-Go consumers.
- **Copy-paste per repo:** No version control, diverges over time. Rejected immediately.
