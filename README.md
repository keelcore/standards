# keelcore/standards

Engineering standards for keelcore projects. Single source of truth for coding, CI, and bash.
Consumed by AI coding tools (Claude, Cursor, Copilot) and human contributors alike.

## Governance

| File | Scope |
| --- | --- |
| [governance/coding.md](governance/coding.md) | All code edits — scope control, reviewability, safety |
| [governance/ci.md](governance/ci.md) | CI workflows and scripts — supply chain, coverage, permissions |
| [governance/bash.md](governance/bash.md) | Bash scripts — portability, structure, logging |
| [governance/platform.md](governance/platform.md) | Platform architecture — governance process, DNS, TLS, WAF, networking |
| [governance/observability.md](governance/observability.md) | Metrics, logging, tracing, alerting |
| [governance/security.md](governance/security.md) | IAM, encryption, key management, data classification |
| [governance/runtime.md](governance/runtime.md) | Containers, orchestration, deployment, compliance |
| [governance/api-management.md](governance/api-management.md) | API design, versioning, rate limiting, quotas, gateway |

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
| --- | --- |
| Claude Code | [adapters/claude/CLAUDE.md](adapters/claude/CLAUDE.md) |
| Cursor | [adapters/cursor/](adapters/cursor/) |
| GitHub Copilot | [adapters/copilot/copilot-instructions.md](adapters/copilot/copilot-instructions.md) |

## Architecture Decision Records

ADRs documenting standards design decisions live in [docs/adr/](docs/adr/).

New ADRs use the template at [docs/adr/0000-template.md](docs/adr/0000-template.md).

| ADR | Decision |
| --- | --- |
| [0001](docs/adr/0001-standards-as-submodule-and-package.md) | Standards distributed as both submodule and language package |
| [0002](docs/adr/0002-coverage-baseline-in-repo.md) | Code coverage baseline stored in repository |
| [0003](docs/adr/0003-architecture-governance-process.md) | Architecture governance via DACI, RFC, and ARB |
| [0004](docs/adr/0004-workload-identity-spiffe-spire.md) | SPIFFE/SPIRE for workload identity |
| [0005](docs/adr/0005-observability-opentelemetry.md) | OpenTelemetry as the unified observability framework |
| [0006](docs/adr/0006-opa-centralized-policy-engine.md) | OPA as the centralized authorization policy engine |
| [0007](docs/adr/0007-zero-downtime-deployment.md) | Zero-downtime deployment via blue/green and canary |
| [0008](docs/adr/0008-rapid-key-rotation.md) | Rapid key rotation with a 5-minute platform SLA |
| [0009](docs/adr/0009-gitops-change-management.md) | GitOps as the declarative change management mechanism |

## Versioning

Semantic versioning. Tags trigger publication to all package ecosystems simultaneously.

- Breaking changes (governance removals, renamed files): major version bump.
- New governance or expanded rules: minor version bump.
- Corrections, clarifications: patch version bump.
