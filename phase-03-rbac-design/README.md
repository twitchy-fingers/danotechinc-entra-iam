# Phase 03: RBAC Design

> **Status: Planned.** This README outlines the scenario and scope. The full architecture, diagrams and `WALKTHROUGH.md` are added when the phase is built.

## Scenario

Today access is granted by copying a colleague. Oliver Hughes (CISO) wants every permission traceable to a business role. The IAM team works with department heads, such as Kwame Asante (CFO) for Finance and Marcus Thompson (CRO) for Sales, to define birthright and role-based access.

## Planned scope

- Business role catalogue derived from job codes and levels
- Permission matrix: role × application × entitlement
- Separation-of-duties rules (for example, AP Specialist can't approve payments)
- Access policy document approved by the CISO

## Depends on

Phase 02.

**Previous:** [Phase 02](../phase-02-identity-data-model/) · **Next:** [Phase 04](../phase-04-jml-lifecycle/)
