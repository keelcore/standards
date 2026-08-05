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
#   2. Adds release-sbom / release-sign, whose scripts stay standards-private.
#      (All other release/verify scripts now ship byte-identical under Rule A,
#      so their targets live in templates/Makefile.canonical, not here.)

ifeq (,$(wildcard templates/Makefile.canonical))
$(error templates/Makefile.canonical not found — run make from the standards repo root.)
endif

include templates/Makefile.canonical

## Standards-private targets. sbom/sign stay here (not shipped to consumers).
## release-go/npm/pypi, verify-go, and bootstrap-standards moved to
## templates/Makefile.canonical now that Rule A ships their scripts consumer-side.

.PHONY: release-sbom release-sign

release-sbom:
	@echo "📋 Generating SBOM..."
	bash scripts/release/sbom.sh

release-sign:
	@echo "✍️  Signing artifacts..."
	bash scripts/release/sign.sh
