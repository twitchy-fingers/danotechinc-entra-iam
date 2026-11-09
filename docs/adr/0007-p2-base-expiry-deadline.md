# ADR-0007: Licence base expires 20 November: compressed schedule and expiry runbook

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Chukwuemeka Eze (CIO), Adaeze Nwosu (IAM Manager), Oliver Hughes (CISO)
- **Phase:** 00 (program-level). Amends [ADR-0006](0006-trial-window-build-order-and-licensed-cohort.md).

## Context
The Microsoft Entra ID P2 trial expires on **20 November 2026**. Entra Suite is an add-on that requires an active Entra ID P1 or P2 base; if the prerequisite expires, ID Governance scenarios may stop functioning. Conditional Access itself is a P1 feature. The effective deadline for every licence-dependent feature is therefore 20 November, not the Suite expiry of 22 December. No additional licences will be purchased.

## Decision
1. **All licence-dependent work is built and evidenced by 19 November** on the compressed schedule in [`licensing.md`](../licensing.md). Build order is unchanged from ADR-0006.
2. **Licence-independent phases** (08, 09, 10, 11, 14, the KQL part of 15, 16, 17, 18) follow afterwards. Each phase re-checks its own licensing requirements when it is built.
3. **Live HR events inside the window are used as evidence:** joiners on 9 and 16 November, a transfer on 10 November, and departures on 13 November (Ebere Bello, replacing Edem Tetteh, who leaves after the deadline) and 17 November (intern Danielle Brown, whose internship HR ends early). See [`hr-changes.csv`](../../phase-04-jml-lifecycle/hr-changes/hr-changes.csv).
4. **An expiry runbook runs on 20 November** (below) so the tenant is never left without MFA or administrative access.

## Expiry runbook (20 November 2026)
| Step | Action | Why |
|---|---|---|
| 1 | Re-run every phase's evidence scripts and export configuration (CA policies, PIM settings, access packages, reviews, workflows) to `evidence/` | Proof the controls were implemented and operated during the licence period |
| 2 | Sign in with **both break-glass accounts** and confirm Global Administrator works | Break-glass holds a permanent assignment and doesn't depend on PIM |
| 3 | Give `adm.daniel.opara` an **active** Global Administrator assignment (time-bound, 30 days) | PIM activation may not work without the licence; avoid relying on eligibility |
| 4 | Set CA000, CA001 and CA100 to **Off**, then **enable security defaults** | Restores tenant-wide MFA and legacy-auth blocking on the free tier |
| 5 | Record what stopped working, with screenshots | Input for Phase 18 lessons learned |

## Consequences
- About two days per licence-dependent phase; little slack for rework. Design questions are asked up front.
- After 20 November the tenant runs on security defaults. Phase 07's Zero Trust policies remain in Git and in the evidence, but aren't enforced.
- Phases 12 and 13 run short campaigns (days, not weeks) so they complete inside the window.
