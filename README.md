# keelcore/standards

Engineering standards for keelcore projects. Single source of truth for coding, CI, and bash.
Consumed by AI coding tools (Claude, Cursor, Copilot) and human contributors alike.

## Governance

| File | Scope |
|---|---|
| [governance/coding.md](governance/coding.md) | All code edits — scope control, reviewability, safety |
| [governance/ci.md](governance/ci.md) | CI workflows and scripts — supply chain, coverage, permissions |
| [governance/bash.md](governance/bash.md) | Bash scripts — portability, structure, logging |

## Consumption

### Submodule (default, language-agnostic)

```bash
git submodule add git@github.com:keelcore/standards .standards
git submodule update --init --recursive
```

Reference governance from your tool adapters via relative paths (`.standards/governance/coding.md`).

Update to latest:
```bash
git submodule update --remote .standards
git add .standards && git commit -m "chore: update standards"
```

### Go

```bash
go get github.com/keelcore/standards/go
```

Add to your repo:
```go
//go:generate go run github.com/keelcore/standards/go/cmd/materialize .standards
```

Then run `go generate ./...` to extract governance files to `.standards/` (gitignore this directory).

### Node

```bash
npm install @keelcore/standards
```

Governance files are available under `node_modules/@keelcore/standards/governance/`.

### Python

```bash
pip install keelcore-standards
```

## Tool Adapters

Copy the relevant adapter to your repo and adjust paths if needed.

| Tool | Adapter |
|---|---|
| Claude Code | [adapters/claude/CLAUDE.md](adapters/claude/CLAUDE.md) |
| Cursor | [adapters/cursor/](adapters/cursor/) |
| GitHub Copilot | [adapters/copilot/copilot-instructions.md](adapters/copilot/copilot-instructions.md) |

## Architecture Decision Records

ADRs documenting standards design decisions live in [docs/adr/](docs/adr/).

New ADRs use the template at [docs/adr/0000-template.md](docs/adr/0000-template.md).

## Versioning

Semantic versioning. Tags trigger publication to all package ecosystems simultaneously.

- Breaking changes (governance removals, renamed files): major version bump.
- New governance or expanded rules: minor version bump.
- Corrections, clarifications: patch version bump.