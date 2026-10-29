# Phase 02: Identity Source and HR Data Model

> **Status: Planned.** This README outlines the scenario and scope. The full architecture, diagrams and `WALKTHROUGH.md` are added when the phase is built.

## Scenario

Folasade Adeyemi (CPO) and Tunde Afolabi (HR Operations) own the HR system. Before any account is provisioned, the IAM team and HR agree what every attribute means, which values are valid and who fixes bad data. A wrong department in HR becomes wrong access in every app.

## Planned scope

- Formal attribute contract between HR and IAM (built on [`data/hr`](../data/hr/README.md))
- Data quality rules: required fields, valid job codes, manager must exist and be active
- Python validator that rejects a bad HR file before it reaches Entra ID
- UPN generation and collision rules

## Depends on

Phase 01.

**Previous:** [Phase 01](../phase-01-tenant-foundation/) · **Next:** [Phase 03](../phase-03-rbac-design/)
