# keelcore/standards — Master Orchestrator
# All CI concerns are invoked through this file.
# Workflow YAML calls `make <target>`; developers call the same targets locally.

.PHONY: build lint lint-newlines lint-bash lint-markdown \
        test unit-test integration-test clean audit \
        ci-pr-policy ci-secret-scan ci-dco ci-coverage-delta \
        ci-governance-gate ci-coverage-no-regression \
        coverage coverage-go coverage-rust coverage-baseline-init \
        governance-refresh migrate-makefile \
        check-adr-metadata check-governance-metadata check-rfc-metadata \
        check-legal-drift release-sbom release-sign release-go release-npm release-pypi \
        setup-bats setup-markdownlint setup-shellcheck setup-syft \
        verify-canonical verify-go install-hooks \
        format lint-all pre-commit bootstrap-standards help

## Universal canonical targets (language-independent; mandated by CI standards)

build:
	@echo "🔨 Running build..."
	bash scripts/build.sh

lint: lint-newlines lint-markdown lint-bash

test: unit-test integration-test

unit-test:
	@echo "🧪 Running unit tests..."
	bash scripts/unit-test.sh

integration-test:
	@echo "🧪 Running integration tests..."
	bash scripts/integration-test.sh

clean:
	@echo "🧹 Cleaning..."
	bash scripts/clean.sh

## Audit

audit:
	@echo "🔍 Running CI/Makefile audit..."
	bash scripts/ci/audit-make-targets.sh

## Lint targets

lint-newlines:
	@echo "🔍 Checking trailing newlines..."
	bash scripts/lint/newlines.sh

lint-bash:
	@echo "🔍 Running shellcheck..."
	bash scripts/lint/shellcheck.sh

# Markdown lint via markdownlint-cli2 (the single canonical md linter).
# `lint-md` (the legacy markdownlint-cli wrapper) was removed in the
# governance refactor 2026-05-24 because its recipe pointed at a script that
# never existed (`scripts/lint/md.sh`); Rule 5 of the audit surfaced this.
lint-markdown:
	@echo "🔍 Running markdown lint (markdownlint-cli2)..."
	bash scripts/lint/markdown.sh

## Check targets

check-adr-metadata:
	@echo "🔍 Checking ADR metadata..."
	bash scripts/check/adr-metadata.sh

check-governance-metadata:
	@echo "🔍 Checking governance metadata..."
	bash scripts/check/governance-metadata.sh

check-rfc-metadata:
	@echo "🔍 Checking RFC metadata..."
	bash scripts/check/rfc-metadata.sh

check-legal-drift:
	@echo "⚖️  Checking legal file drift..."
	bash scripts/check-legal-drift.sh

## CI gate targets

ci-pr-policy:
	@echo "🔍 Running PR policy check..."
	bash scripts/ci/pr-policy.sh

ci-secret-scan:
	@echo "🔍 Running secret scan..."
	bash scripts/ci/secret-scan.sh

ci-dco:
	@echo "🔍 Running DCO sign-off check..."
	bash scripts/ci/dco-check.sh

ci-coverage-delta:
	@echo "📊 Checking coverage delta..."
	bash scripts/test/coverage-delta.sh

# Governance CI gate: dry-run reconciliation; non-zero exit on pending change.
# PR with stale governance fails this gate and cannot merge.
ci-governance-gate:
	@echo "🚦 Governance CI gate (governance-refresh --dry-run)..."
	bash scripts/ci/governance-gate.sh

## Coverage
# Aggregator pattern: `make coverage` runs the per-language scripts; each
# script gates on its own scope-detection (no go.mod / no Cargo.toml ⇒ skip
# with exit 0). The gate lives in the script, not in the Makefile, so a
# downstream repo with only one language is silently fine.

coverage: coverage-go coverage-rust

coverage-go:
	@echo "📊 Go coverage..."
	bash scripts/test/coverage-go.sh

coverage-rust:
	@echo "📊 Rust coverage (cargo-llvm-cov)..."
	bash scripts/test/coverage-rust.sh

# Per-file coverage no-regression + 95% new-file floor.
# Implements .standards/governance/testing.md "Coverage Regression Policy".
# CI runs this as a required PR gate.
ci-coverage-no-regression:
	@echo "🚦 coverage-no-regression (per-file)..."
	bash scripts/test/coverage-no-regression.sh

# Operator one-shot: capture current LCOV as the baseline. Run once per
# repo, then again only after an approved coverage-increasing change.
coverage-baseline-init:
	@echo "🪴 coverage-baseline-init (capture current LCOV)..."
	bash scripts/test/coverage-baseline-init.sh

## Release targets

release-sbom:
	@echo "📋 Generating SBOM..."
	bash scripts/release/sbom.sh

release-sign:
	@echo "✍️  Signing artifacts..."
	bash scripts/release/sign.sh

release-go:
	@echo "🚀 Publishing Go module..."
	bash scripts/release/go-publish.sh

release-npm:
	@echo "🚀 Publishing npm package..."
	bash scripts/release/npm-publish.sh

release-pypi:
	@echo "🚀 Publishing PyPI package..."
	bash scripts/release/pypi-publish.sh

## Setup targets

setup-bats:
	@echo "🔧 Installing bats-core test harness..."
	bash scripts/ci/setup-bats.sh

setup-markdownlint:
	@echo "🔧 Installing markdownlint-cli..."
	bash scripts/ci/setup-markdownlint.sh

setup-shellcheck:
	@echo "🔧 Installing shellcheck..."
	bash scripts/ci/setup-shellcheck.sh

setup-syft:
	@echo "🔧 Installing syft..."
	bash scripts/ci/setup-syft.sh

## Pre-commit hook installation (symlinks scripts/git_precommit.sh into .git/hooks)

install-hooks:
	@echo "🪝 Installing git pre-commit hook..."
	bash scripts/install-hooks.sh

## Canonical script verification

verify-canonical:
	@echo "🔍 Verifying canonical scripts in downstream repo (REPO=<path>)..."
	bash scripts/ci/verify-canonical-scripts.sh $(REPO)

## Verify targets

verify-go:
	@echo "🔍 Verifying Go module..."
	bash scripts/verify/go.sh

## Utility targets

format:
	@echo "🖊️  Formatting repository..."
	bash scripts/format.sh

lint-all:
	@echo "🔍 Running all linters (full suite)..."
	bash scripts/lint.sh

pre-commit:
	@echo "🪝 Running pre-commit checks..."
	bash scripts/git_precommit.sh

## Bootstrap entrypoint (downstream consumers invoke this from THEIR repo root)

bootstrap-standards:
	bash scripts/bootstrap-standards.sh

## Governance reconciliation (downstream consumers; ongoing, not first-time)
# Syncs canonical scripts from .standards/scripts/ to consumer scripts/ and
# injects any missing canonical Makefile target from .standards/templates/Makefile
# into consumer Makefile. `.standards` wins. Idempotent.
governance-refresh:
	bash scripts/governance-refresh.sh

## One-shot migration for consumers whose Makefile is a clone of the
## pre-include-era templates/Makefile. Adds the include directive and
## removes canonical target blocks. Idempotent (no-op if already migrated).
## First-time invocation: `bash .standards/scripts/migrate-makefile.sh`
## After migration: `make migrate-makefile` (no-op on re-run).
migrate-makefile:
	bash scripts/migrate-makefile.sh

## Help (auto-enumerates targets across every file in $(MAKEFILE_LIST) so
## consumers including this Makefile see their own targets alongside the
## canonical ones). Logic lives in scripts/help.sh per the audit's single-
## script-invocation rule.

help:
	bash scripts/help.sh $(MAKEFILE_LIST)
