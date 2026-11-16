# ADR-0005: Layered RBAC model with simulation gate

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Oliver Hughes (CISO), Chukwuemeka Eze (CIO), Adaeze Nwosu (IAM Manager)
- **Phase:** 03

## Context
Access at DanotechInc is granted by copying other users (finding F-06), so nobody can explain why most access exists. The new model must grant access automatically from HR data, keep privileged access out of automation, enforce separation of duties, and be verifiable before it acts on real accounts.

## Decision
1. **Five role layers:** Birthright, Department and Job roles are automatic (dynamic groups from HR attributes); Privileged roles have named employee members and are PIM-eligible; Requestable roles are access packages with approval and expiry.
2. **One role = one Entra ID group.** Applications are assigned to groups, never to individual users.
3. **The model is data** (`model/*.csv`), not documentation. A simulation (`build_access_model.py`) applies it to the full HR feed and must pass before any change is implemented. Dynamic group rules for Phase 05 are generated from the same data.
4. **High and Privileged entitlements are employee-only**; where a job is shared with contractors, the role is split by employee type (e.g. `JR-SEC-SOC` / `JR-SEC-SOC-LIMITED`).
5. **SoD exceptions** are recorded with a compensating control, two approvers and an expiry no more than 6 months away; the simulation fails after expiry.

## Alternatives considered
| Option | Why not chosen |
|---|---|
| Role mining from existing access | Would formalise years of accumulated "copy Ama" access. |
| One role per job code (flat model) | 73 near-duplicate roles; shared access (department spaces, manager approval) repeated in each. |
| Assign apps directly to department groups only | Too coarse: everyone in Finance would be able to release payments. |
| Design in documents only, no simulation | No way to know what 200 people actually receive until it's live. |

## Consequences
- A job code change in HR changes access automatically, so movers stop accumulating access.
- Role changes need a PR and a passing simulation, which slows ad-hoc changes deliberately.
- Rachel Okafor's SoD exception (EXC-001) must be re-approved before 2027-05-05, or the simulation fails.
- Phase 12 must configure `RQ-GH-REPO-ADMIN` as incompatible with production deploy rights (SOD-02).
