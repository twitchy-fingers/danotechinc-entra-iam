# ADR-0008: JML automation design

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Adaeze Nwosu (IAM Manager), Tunde Afolabi (HR Operations Manager), Oliver Hughes (CISO)
- **Phase:** 04

## Context
Phase 04 connects the HR feed to Entra ID and automates joiner, mover and leaver tasks. DanotechInc has no mailboxes (ADR-0001), the licence window closes on 20 November (ADR-0007), and the feed starts as a manual process.

## Decision
1. **API-driven inbound provisioning** from a PowerShell client. Every run builds the day's HR snapshot, passes the Phase 02 quality gate (including the mass-change guard), transforms to SCIM and uploads in batches of 50, managers first. The run is manual until the licence-dependent phases are complete, then scheduled.
2. **HR status controls account enablement.** Provisioning sets `accountEnabled` from HR status and end date. Lifecycle Workflows never enable accounts, so a joiner HR hasn't confirmed (e.g. Nicole Reed) stays disabled.
3. **Joiners get a one-time Temporary Access Pass, never a password.** WF-02 emails it to the manager on the hire date (24-hour lifetime, single use); the joiner uses it once to register a passkey. Lab-only: managers' `mail` attributes are plus-addresses of one external inbox. Fallback: issue the TAP in the portal (Authentication methods).
4. **Leavers are disabled at the end of their last day and deleted 7 days later.** WF-04 runs at the first schedule after the last day (offset +1): disable, revoke sessions, notify the manager. WF-05 deletes at +7 days (lab value; production would use 30+). The feed sends a Terminated record only if an account with that employeeId exists, so a deleted user is never recreated, and someone who left before the first load is never created.
5. **Movers' access changes through dynamic groups** (Phase 05), not workflow tasks. WF-03 only notifies the manager, so a human sees the change.
6. **Two independent safety nets against mass disablement:** the DQ-21 guard (10% of records disappearing) and the provisioning service's accidental-deletion threshold (20 operations).

## Alternatives considered
| Option | Why not chosen |
|---|---|
| Lifecycle Workflow "Enable user account" on the hire date | Would enable accounts HR hasn't confirmed. |
| Random initial passwords | Passwords get shared in chat and reused; a TAP is single-use and leads straight to passkey registration. |
| Disable at the start of the last day (offset 0) | Cuts people off during their final working day. |
| Delete immediately | No recovery window for mistakes; leavers' data owners need time to transfer ownership. |

## Consequences
- Workflows must exist before the first trigger date they should cover; Nicole Reed (hire date before deployment) is handled with an on-demand run.
- On-demand and scheduled workflow results are exported as evidence by `07-Get-JmlEvidence.ps1`.
- After 20 November, Lifecycle Workflows stop; leaver disablement then relies on the HR feed alone until licences return.
