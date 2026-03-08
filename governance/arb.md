# Architecture Review Board (ARB)

**Maturity:** Required
**Version:** 1.0.0
**Last Reviewed:** 2026-03-09

The ARB is the governing body for platform architecture decisions. It is the default Approver
for all architecture ADRs and the final escalation point for cross-domain technical disputes.

## Membership

### Composition

1. The ARB has a minimum of 5 members and a maximum of 9 members.
2. Members are nominated by the CTO and serve a minimum term of 12 months.
3. Required seats (one each): Infrastructure, Security, Observability, Data, Application Platform.
4. The CTO or a designated VP of Engineering holds the Chair seat. The Chair is a non-voting
   member except to break ties (see Tie-Breaking below).
5. Membership is documented in the internal people directory and in this file's companion
   `docs/arb-members.md` (maintained separately from this governance doc to avoid churn).

### Eligibility

6. Members must be active engineers or engineering managers with direct responsibility in their
   domain. Advisory or external members are not permitted.
7. A member who misses three consecutive meetings without proxy is automatically suspended
   pending review by the Chair.

## Meeting Cadence

8. The ARB meets on a defined monthly cadence. The meeting schedule is published at the start
   of each quarter.
9. Emergency sessions may be called by the Chair or by any two members with a minimum 24-hour
   notice. Emergency sessions are limited to the agenda item that triggered them.
10. Meeting notes and decisions are published to the engineering wiki within five business days.
11. Decisions made asynchronously (via PR approval or written vote) are recorded with the same
    formality as decisions made in session.

## Decision-Making

### Quorum

12. Quorum is a simple majority of seated, non-suspended members (excluding the Chair):
    - 5 members: quorum = 3
    - 7 members: quorum = 4
    - 9 members: quorum = 5
13. Decisions made without quorum are provisional. They must be ratified at the next session
    where quorum is present, or they are void.
14. A member who has a conflict of interest in a decision must declare it and recuse. Recused
    members do not count toward quorum for that item.

### Voting

15. Decisions are made by simple majority of present, non-recused members.
16. Votes are recorded (member, vote, rationale for dissent) in the meeting notes.
17. Abstentions are permitted but discourage without stated reason.

### Tie-Breaking

18. When a vote is tied, the Chair casts the deciding vote.
19. The Chair must state their rationale when casting a tie-breaking vote.
20. Tie-breaking decisions are flagged in meeting notes for CTO awareness.

## Scope of Authority

21. The ARB has authority over: platform architecture standards, vendor selection for
    platform-level tooling, cross-domain API contracts, security architecture, and
    data architecture patterns.
22. The ARB does not have authority over: team-internal implementation choices, product
    roadmap prioritization, staffing decisions, or budget approval.
23. Any team may bring a decision to the ARB for guidance even if ARB approval is not strictly
    required. The ARB may accept or decline to review.

## ADR and RFC Approval

24. The ARB is the default Approver for all ADRs tagged as architecture decisions.
25. The ARB reviews RFCs at the Under Discussion stage. Approval converts an RFC to Accepted
    and triggers ADR creation.
26. The ARB may delegate Approver authority for a specific decision to a named individual or
    sub-committee. Delegation is recorded in the relevant ADR/RFC.
27. The ARB chair may approve urgent security-related ADRs unilaterally with 24-hour notice
    to the full board, subject to ratification at the next session.

## Escalation

28. Escalation path: Team → Domain Lead → ARB → CTO.
29. Any engineer may escalate a decision to the ARB by opening a GitHub issue in the
    `keelcore/standards` repository labeled `arb-escalation`.
30. The ARB must acknowledge escalations within three business days and schedule review
    within ten business days.
31. ARB decisions may be escalated to the CTO only on the grounds of: process violation,
    conflict of interest, or organizational policy conflict. The CTO's decision is final.
32. Escalation outcomes are published (with appropriate confidentiality) in the engineering wiki.

## Standards Cadence

33. The ARB publishes a versioned Architecture Standards snapshot at least once per quarter.
    The snapshot is tagged in this repository as `arb-standards-YYYY-QN`.
34. Each quarterly snapshot includes: new ADRs accepted since the last snapshot, standards
    that changed maturity level, deprecated standards, and open RFCs in progress.
35. The ARB reviews all standards marked `Deprecated` at least once per year to confirm
    retirement or rescind deprecation.

## Do Not

- Allow a decision with quorum impact to proceed if quorum is not met.
- Allow a member to vote on a decision where they have a declared conflict of interest.
- Publish meeting notes without removing information subject to legal hold or HR confidentiality.
- Allow the Chair to cast a non-tie-breaking vote.
- Make ARB decisions without recording them in the engineering wiki within five business days.
