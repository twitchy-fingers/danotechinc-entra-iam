# Phase 05: Groups, App Roles and OIDC Test App

> **Status: Planned.** This README outlines the scenario and scope. The full architecture, diagrams and `WALKTHROUGH.md` are added when the phase is built.

## Scenario

With 200 users in the tenant, access needs to follow attributes automatically. Department and job-code dynamic groups give birthright access; assigned groups cover exceptions with named owners. A small internal app proves role-based authorization end to end.

## Planned scope

- Dynamic groups by department, job code, location and employee type
- Assigned groups with owners and expiry
- Group-based licensing (`GRP-LIC-*`)
- OIDC test app with app roles mapped to groups

## Depends on

Phase 04.

**Previous:** [Phase 04](../phase-04-jml-lifecycle/) · **Next:** [Phase 06](../phase-06-privileged-access/)
