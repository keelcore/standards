# keelcore/standards — Master Orchestrator
# All CI concerns are invoked through this file.
# Workflow YAML calls `make <target>`; developers call the same targets locally.

.PHONY: build lint lint-newlines lint-md lint-bash lint-markdown \
        test unit-test integration-test clean audit \
        ci-pr-policy ci-secret-scan ci-dco ci-coverage-delta \
        coverage check-adr-metadata check-governance-metadata check-rfc-metadata \
        check-legal-drift release-sbom release-sign release-go release-npm release-pypi \
        setup-markdownlint setup-shellcheck setup-syft verify-canonical verify-go \
        format lint-all pre-commit help

## Universal canonical targets (language-independent; mandated by CI standards)

build:
	@echo "✅ Nothing to build (standards is a documentation repository)"

lint: lint-newlines lint-md lint-bash

test: unit-test integration-test

unit-test:
	@echo "✅ No unit tests (standards is a documentation repository)"

integration-test:
	@echo "✅ No integration tests (standards is a documentation repository)"

clean:
	@echo "🧹 Nothing to clean (standards is a documentation repository)"

## Audit

audit:
	@echo "🔍 Running CI/Makefile audit..."
	./scripts/ci/audit-make-targets.sh

## Lint targets

lint-newlines:
	@echo "🔍 Checking trailing newlines..."
	./scripts/lint/newlines.sh

lint-md:
	@echo "🔍 Running markdown lint (markdownlint-cli)..."
	./scripts/lint/md.sh

lint-bash:
	@echo "🔍 Running shellcheck..."
	./scripts/lint/shellcheck.sh

lint-markdown:
	@echo "🔍 Running markdown lint (markdownlint-cli2)..."
	./scripts/lint/markdown.sh

## Check targets

check-adr-metadata:
	@echo "🔍 Checking ADR metadata..."
	./scripts/check/adr-metadata.sh

check-governance-metadata:
	@echo "🔍 Checking governance metadata..."
	./scripts/check/governance-metadata.sh

check-rfc-metadata:
	@echo "🔍 Checking RFC metadata..."
	./scripts/check/rfc-metadata.sh

check-legal-drift:
	@echo "⚖️  Checking legal file drift..."
	./scripts/check-legal-drift.sh

## CI gate targets

ci-pr-policy:
	@echo "🔍 Running PR policy check..."
	./scripts/ci/pr-policy.sh

ci-secret-scan:
	@echo "🔍 Running secret scan..."
	./scripts/ci/secret-scan.sh

ci-dco:
	@echo "🔍 Running DCO sign-off check..."
	./scripts/ci/dco-check.sh

ci-coverage-delta:
	@echo "📊 Checking coverage delta..."
	./scripts/test/coverage-delta.sh

## Coverage

coverage:
	@echo "📊 Generating coverage report..."
	./scripts/test/coverage.sh

## Release targets

release-sbom:
	@echo "📋 Generating SBOM..."
	./scripts/release/sbom.sh

release-sign:
	@echo "✍️  Signing artifacts..."
	./scripts/release/sign.sh

release-go:
	@echo "🚀 Publishing Go module..."
	./scripts/release/go-publish.sh

release-npm:
	@echo "🚀 Publishing npm package..."
	./scripts/release/npm-publish.sh

release-pypi:
	@echo "🚀 Publishing PyPI package..."
	./scripts/release/pypi-publish.sh

## Setup targets

setup-markdownlint:
	@echo "🔧 Installing markdownlint-cli..."
	./scripts/ci/setup-markdownlint.sh

setup-shellcheck:
	@echo "🔧 Installing shellcheck..."
	./scripts/ci/setup-shellcheck.sh

setup-syft:
	@echo "🔧 Installing syft..."
	./scripts/ci/setup-syft.sh

## Canonical script verification

verify-canonical:
	@echo "🔍 Verifying canonical scripts in downstream repo (REPO=<path>)..."
	./scripts/ci/verify-canonical-scripts.sh $(REPO)

## Verify targets

verify-go:
	@echo "🔍 Verifying Go module..."
	./scripts/verify/go.sh

## Utility targets

format:
	@echo "🖊️  Formatting repository..."
	./scripts/format.sh

lint-all:
	@echo "🔍 Running all linters (full suite)..."
	./scripts/lint.sh

pre-commit:
	@echo "🪝 Running pre-commit checks..."
	./scripts/git_precommit.sh

## Help

help:
	@echo "keelcore/standards Build System"
	@echo "Usage: make [target]"
	@echo ""
	@echo "Universal targets (canonical; language-independent):"
	@echo "  build              No-op (documentation repository)"
	@echo "  lint               lint-newlines + lint-md + lint-bash"
	@echo "  test               unit-test + integration-test"
	@echo "  unit-test          No-op (documentation repository)"
	@echo "  integration-test   No-op (documentation repository)"
	@echo "  clean              No-op (documentation repository)"
	@echo "  audit              CI/Makefile standards compliance audit"
	@echo ""
	@echo "Lint:"
	@echo "  lint-newlines      Check trailing newlines (.md .sh .go .yml etc.)"
	@echo "  lint-md            markdownlint-cli check (canonical; from keel)"
	@echo "  lint-bash          shellcheck on all scripts"
	@echo "  lint-markdown      markdownlint-cli2 check (standards native)"
	@echo ""
	@echo "Checks:"
	@echo "  check-adr-metadata         Validate ADR metadata fields"
	@echo "  check-governance-metadata  Validate governance file metadata"
	@echo "  check-rfc-metadata         Validate RFC metadata fields"
	@echo "  check-legal-drift          Verify legal files match source of truth"
	@echo ""
	@echo "CI Gates:"
	@echo "  ci-pr-policy       PR policy gate"
	@echo "  ci-secret-scan     Secret scan (gitleaks)"
	@echo "  ci-dco             DCO Signed-off-by check"
	@echo "  ci-coverage-delta  Coverage delta gate"
	@echo "  coverage           Generate coverage report"
	@echo ""
	@echo "Release:"
	@echo "  release-sbom       Generate SPDX SBOM"
	@echo "  release-sign       Sign artifacts (cosign)"
	@echo "  release-go         Publish Go module"
	@echo "  release-npm        Publish npm package"
	@echo "  release-pypi       Publish PyPI package"
	@echo ""
	@echo "Setup:"
	@echo "  setup-markdownlint Install markdownlint-cli"
	@echo ""
	@echo "Verification:"
	@echo "  verify-canonical REPO=<path>  Check downstream repo scripts match standards"
	@echo "  verify-go                     Build and vet the Go module"
	@echo ""
	@echo "Utilities:"
	@echo "  format             Run all formatters"
	@echo "  lint-all           Run full linter suite (scripts/lint.sh)"
	@echo "  pre-commit         Run pre-commit checks"
