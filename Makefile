# keelcore/standards — STANDARDS-PRIVATE Makefile.
#
# Not for downstream consumer use. Consumers get the canonical universal
# targets by including .standards/templates/Makefile.canonical from their
# OWN top-level Makefile (the seed template is at
# templates/Makefile.consumer).
#
# This file:
#   1. Includes the same canonical ruleset consumers do — so the standards
#      repo `dogfoods` itself (running `make audit` here exercises the same
#      target shapes downstream repos do).
#   2. Adds targets whose recipes call scripts intentionally NOT shipped to
#      consumers (the governance-refresh ship-filter excludes
#      scripts/release/ and scripts/verify/, plus scripts/bootstrap-standards.sh
#      which consumers `curl` once rather than keep locally).

ifeq (,$(wildcard templates/Makefile.canonical))
$(error templates/Makefile.canonical not found — run make from the standards repo root.)
endif

include templates/Makefile.canonical

## Standards-only targets (not shipped to consumers)

.PHONY: release-sbom release-sign release-go release-npm release-pypi \
        verify-go bootstrap-standards

## Release targets — driven by scripts/release/, which governance-refresh
## intentionally excludes from the consumer ship list.

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

## Per-language verify (scripts/verify/ is standards-only).

verify-go:
	@echo "🔍 Verifying Go module..."
	bash scripts/verify/go.sh

## Bootstrap entrypoint — consumers invoke this from THEIR repo root via a
## one-shot curl of the script; the script itself is not kept in consumer
## scripts/. The standards repo exposes the target for local rehearsal.

bootstrap-standards:
	bash scripts/bootstrap-standards.sh
