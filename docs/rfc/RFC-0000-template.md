# RFC-0000: Title

**RFC-ID:** RFC-0000
**Date:** YYYY-MM-DD
**Status:** Draft | Under Discussion | Accepted | Rejected | Withdrawn | Implemented
**Driver:** Name or team authoring this RFC
**Approver:** ARB | Name
**Contributors:** Names or teams whose input was sought
**Informed:** Names, teams, or groups notified of the outcome
**Related ADR:** N/A | ADR-XXXX (populated when RFC is accepted and converted to an ADR)

---

## Summary

One paragraph. What is being proposed and why?

## Motivation

What problem does this solve? What is the current pain point, gap, or risk?
Include data or examples where possible.

## Proposal

Detailed description of the proposed change. Include:

- What will change
- What will not change
- Migration or rollout plan
- Rollback plan

## Alternatives Considered

What other options were evaluated? Why is this proposal preferred?

## Open Questions

List unresolved questions that need input during the Discussion phase.

- [ ] Question 1
- [ ] Question 2

## Acceptance Criteria

What must be true for this RFC to be considered Implemented?

- [ ] Criterion 1
- [ ] Criterion 2

---

## RFC Lifecycle

| Status | Meaning |
|---|---|
| Draft | Author is preparing the proposal; not yet open for comment |
| Under Discussion | PR is open; contributors are reviewing and commenting |
| Accepted | Approver has signed off; RFC will proceed to implementation |
| Rejected | Approver has declined; rationale recorded in comments |
| Withdrawn | Driver has withdrawn the proposal before a decision |
| Implemented | Acceptance criteria met; a corresponding ADR has been created |

**Process:**

1. Driver creates `docs/rfc/RFC-NNNN-short-title.md` from this template and opens a PR.
2. PR is labeled `rfc` and `status: under-discussion`.
3. Contributors review and comment. Minimum comment period: 5 business days.
4. Approver (default: ARB) accepts or rejects. Decision recorded in PR and in the RFC file.
5. On acceptance: RFC status → Accepted. Driver opens a follow-up ADR. On ADR acceptance, RFC status → Implemented.
6. On rejection: RFC status → Rejected. Rationale summarized in the RFC file.
