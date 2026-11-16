# ADR-0006: Build order within the trial window, and a 25-seat licensed cohort

- **Status:** Accepted; schedule and deadline amended by [ADR-0007](0007-p2-base-expiry-deadline.md)
- **Date:** 2026-11-05
- **Deciders:** Chukwuemeka Eze (CIO), Adaeze Nwosu (IAM Manager), Oliver Hughes (CISO)
- **Phase:** 00 (program-level)

## Context
The Microsoft Entra Suite trial has **25 seats** and expires on **22 December 2026**, 47 days after recording. The program has 19 phases. Six of them depend on Suite or P2 features: Lifecycle Workflows (04), PIM (06), risk-based Conditional Access and ID Protection (07, 15), entitlement management (12) and access reviews (13). DanotechInc has 200 people.

## Decision
1. **Re-sequence the build, keep the numbering.** Phase numbers reflect the logical architecture and dependencies and don't change. The *build order* becomes 01 → 02 → 03 → 04 → 05 → 06 → 07 → 12 → 13 → 15 (licence-dependent parts), with evidence captured by 21 December. Phases 08, 09, 10, 11, 14, the rest of 15, 16, 17 and 18 follow after the trial.
2. **Phase 12 uses groups as access package resources.** Phase 08 (application SSO) now comes after Phase 12. That works because the role model maps every role to a group (ADR-0005): access packages grant groups, and Phase 08 later assigns applications to those same groups.
3. **Licences go to a named cohort of 25** ([`licensed-cohort.csv`](../licensed-cohort.csv)): 22 workforce identities and 3 admin accounts, chosen to cover every licence-dependent scenario (joiners, a leaver, a mover, an intern's expiry, contractors, a SoD exception, PIM approvers, access reviewers, risk triage). Licences are assigned through the group `GRP-LIC-EntraSuite` in Phase 05.
4. **All 200 people are still provisioned** by the HR feed. Features applied tenant-wide (for example Conditional Access) may affect unlicensed users; this is documented as a lab-only licensing gap, not a design choice.

## Alternatives considered
| Option | Why not chosen |
|---|---|
| Keep the original order | Phases 12, 13 and 15 would fall after expiry. |
| Provision only 25 people | Would undermine the HR-driven design and the 200-person RBAC simulation. |
| Spread seats evenly by department | Wouldn't guarantee coverage of specific scenarios (live joiner, leaver, intern expiry, SoD exception). |

## Consequences
- Phase 12 access packages initially contain groups only; Phase 08 connects apps to those groups afterwards.
- Phase 15 is split: ID Protection triage before expiry, KQL-driven operations after Phase 14.
- Live HR events inside the window (joiners 9 and 16 Nov, leaver 27 Nov, intern end 18 Dec) are captured as real evidence rather than simulated.
- Before 22 December, the Steering Committee decides whether to purchase licences or accept the gap.
- The P2 trial expiry must also be recorded; if it is earlier than 22 December, this ADR is revisited.
