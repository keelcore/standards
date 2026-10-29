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
# redefined here.

ifeq (,$(wildcard templates/Makefile.canonical))
$(error templates/Makefile.canonical not found — run make from the standards repo root.)
endif

include templates/Makefile.canonical
