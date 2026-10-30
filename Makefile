# keelcore/standards — STANDARDS-PRIVATE Makefile.
#
# Not for downstream consumer use. Consumers get the canonical universal
# targets by including .standards/templates/Makefile.canonical from their
# OWN top-level Makefile (the seed template is at
# templates/Makefile.consumer).
#
# This file includes the same canonical ruleset consumers do — so the
# standards repo `dogfoods` itself (running `make audit` here exercises the
# same target shapes downstream repos do). Every target, release-sbom and
# release-sign included, lives in templates/Makefile.canonical; none is
# redefined here. The only targets defined here are for this repo's own
# *.local.sh hooks, which are never shipped to consumers.

ifeq (,$(wildcard templates/Makefile.canonical))
$(error templates/Makefile.canonical not found — run make from the standards repo root.)
endif

include templates/Makefile.canonical

.PHONY: integration-test-local
.PHONY: create-release-local

## BATS suites under tests/ — also delegated to by canonical integration-test.sh (`make integration-test`)
integration-test-local:
	@echo "🧪 Running standards BATS suites..."
	bash scripts/integration-test.local.sh

## CHANGELOG bump hook (PREV_TAG=vX.Y.Z) — also called by canonical create-release.sh (`make create-release`)
create-release-local:
	@echo "🏷️  Computing bump level from CHANGELOG [Unreleased]..."
	bash scripts/release/create-release.local.sh $(PREV_TAG)
