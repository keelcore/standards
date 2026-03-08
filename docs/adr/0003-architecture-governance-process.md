# ADR-0003: Architecture Governance via DACI, RFC, and ARB

**Date:** 2026-03-09
**Status:** Accepted

## Context

Platform engineering decisions affect many teams and last for years. Without a defined process,
decisions are made ad-hoc, lack clear ownership, are not documented, and cannot be audited or
rolled back. Two failure modes are common: analysis paralysis (no one is empowered to decide)
and rogue decisions (changes shipped without review). A governance process must be lightweight
enough to be used and rigorous enough to produce durable, auditable decisions.

## Decision

We adopt a three-layer governance model:

**1. DACI for decision ownership**
Every architecture decision has four defined roles:
- **Driver** — authors the RFC and owns shepherding it to a decision.
- **Approver** — has final authority (ARB chair or delegate). One Approver per decision.
- **Consulted** — stakeholders whose input is sought before the decision.
- **Informed** — parties notified of the outcome.

DACI ensures there is always one named person accountable for the decision reaching closure.
It eliminates the ambiguity of "the team decided" with no identifiable owner.

**2. RFC process for significant changes**
Any change to platform standards, vendor selection, or network topology requires a written RFC.
The RFC template covers: problem statement, proposed solution, alternatives considered, rollout
plan, and rollback plan. A minimum 5-business-day comment period applies; urgent security
changes compress to 24 hours with ARB chair notification. Accepted RFCs are archived in
`docs/rfc/` with status and acceptance date.

**3. Architecture Review Board (ARB) for cross-cutting decisions**
The ARB meets at a minimum monthly cadence. Decisions and attendance records are published to
the engineering wiki within five business days. The ARB publishes a versioned Architecture
Standards document at least quarterly. All previous versions are permanently archived.
Cross-domain decisions (affecting more than one service domain) require ARB review before
implementation.

ADRs (this document's format) record point-in-time decisions with rationale. RFCs record
proposals in progress. The ARB governs the process and publishes the rolling standards document.
These three artifacts serve different audiences and retention horizons.

## Consequences

**Positive:**
- Every significant decision has a named Driver and Approver — no diffusion of responsibility.
- RFC archives provide a historical record of what was considered and why alternatives were rejected.
- ARB cadence ensures standards drift is detected and corrected quarterly.
- DACI is familiar from other domains (product, program management) — low learning curve.
- Versioned Architecture Standards documents satisfy audit and compliance requirements.

**Negative:**
- RFC process adds latency to decisions. Teams under delivery pressure will feel friction.
- The ARB can become a bottleneck if meeting cadence slips or quorum is not maintained.
- DACI requires discipline to name roles before work starts, not retroactively.
- Maintaining the RFC archive and ARB minutes requires operational overhead.

## Alternatives Considered

### Informal consensus with documented outcomes
Decision made by whoever is in the room; a Confluence page is written afterward. Rejected
because there is no defined Approver, no accountability for reaching closure, and the record
is easily lost or edited without audit trail.

### RFC-only (no DACI, no ARB)
RFCs are written but there is no formal body to approve them. Rejected because RFCs can sit
in review indefinitely without a defined Approver, and cross-cutting concerns have no forum
for adjudication.

### Architecture Decision Records only
ADRs capture decisions but do not prescribe a process for reaching them. Rejected as the sole
mechanism because ADRs alone do not answer: who can approve this, how long does review take,
and who is notified of the outcome.

### Centralized Architecture team makes all decisions
A small team of architects approves all platform changes. Rejected because it creates an
unsustainable bottleneck, reduces domain team ownership, and produces decisions divorced from
implementation context.