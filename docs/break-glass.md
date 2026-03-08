# Break-Glass Procedure

This document defines the procedure for bypassing normal CI and change management controls
when a critical security patch must ship immediately and the standard PR + review + CI cycle
cannot be completed in time.

## When Break-Glass Applies

Break-glass is appropriate only when **all** of the following are true:

1. A critical security vulnerability is confirmed (CVE severity Critical, or active exploit observed).
2. The standard PR workflow cannot complete within the required response window.
3. Delaying shipment creates a materially greater risk than bypassing controls.

Break-glass is **not** appropriate for: feature urgency, release deadlines, flaky CI, or
reviewer unavailability without a security justification.

## Required Authorizations

Before bypassing any control, obtain explicit approval from **two** of the following:

- CTO or VP of Engineering
- ARB Chair
- Security team lead (CISO or equivalent)

Approvals must be recorded in writing (Slack with channel log, email, or incident record).
Verbal approval is not sufficient.

## Procedure

### 1. Open an Incident Record

Create an incident in the incident management platform before or immediately after the
bypass. The incident record must include:

- Timestamp of discovery
- Description of the vulnerability or exploit
- Justification for break-glass
- Names of the two authorizing parties
- Changes to be applied

### 2. Apply the Change

The change may be applied directly to the default branch by a named engineer who has
been authorized. The engineer must:

- Apply the minimum change required to address the vulnerability.
- Not include any non-security-related changes in the same commit.
- Record the commit SHA in the incident record.

### 3. Commit to the GitOps Repository

Within 30 minutes of applying the emergency change, the same change must be committed
to the GitOps repository via a PR. The PR is labeled `break-glass` and may be merged
by a single approver (the second authorizing party) without the standard review period.

### 4. CI Bypass (if required)

If CI must be bypassed:

- The bypassing engineer adds a comment to the PR: `BREAK-GLASS: [incident-id]`.
- A CI administrator enables the bypass for that specific PR only.
- Normal CI is re-enabled immediately after merge.
- The bypass is logged in the audit trail.

### 5. Notify

Within one hour of the change being applied, notify:

- ARB (if not already an authorizing party)
- All engineering leads
- Security team

### 6. Post-Incident Review

Within five business days, conduct a post-incident review covering:

- Root cause of the vulnerability
- Whether break-glass was justified or could have been avoided
- Whether the emergency change introduced any technical debt
- Any process improvements to prevent recurrence

The review outcome is documented and stored in the incident record.

## Audit Trail

All break-glass events are logged as `audit`-classified entries and retained for 7 years.
The log includes: incident ID, authorizing parties, engineer who applied the change,
commit SHA, timestamps, and post-incident review link.

## Contacts

Authorizing parties and their escalation contacts are maintained in the internal directory.
This document intentionally does not embed contact details to avoid staleness.
