# Phase 04: JML Lifecycle Automation

> **Status: Planned.** This README outlines the scenario and scope. The full architecture, diagrams and `WALKTHROUGH.md` are added when the phase is built.

## Scenario

Nicole Reed starts as an Account Executive on 2 November 2026; Sofía Reyes leaves Sales on 6 November; Halima Akinola's engineering contract ends in May 2027. Each must get, change or lose access automatically, driven only by the HR feed.

## Planned scope

- API-driven inbound provisioning from `employees.csv` via the bulk upload endpoint
- Lifecycle Workflows: pre-hire, day-one, mover and leaver tasks
- Mover scenarios applied as HR change files (promotions, transfers)
- Adoption of Daniel Opara's existing account by `employeeId`

## Depends on

Phase 03.

**Previous:** [Phase 03](../phase-03-rbac-design/) · **Next:** [Phase 05](../phase-05-groups-app-roles/)
