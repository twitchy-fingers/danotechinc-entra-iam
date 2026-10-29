# Phase 11: Agent-to-Tool Authorization

> **Status: Planned.** This README outlines the scenario and scope. The full architecture, diagrams and `WALKTHROUGH.md` are added when the phase is built.

## Scenario

The Service Desk wants an AI agent that can look up users, reset MFA registrations and open tickets, but sensitive actions must be approved by a human on Grace Robinson's team.

## Planned scope

- Agent identity with scoped, least-privilege tool APIs
- OAuth scopes per tool; on-behalf-of vs app-only decisions
- Human-in-the-loop approval for high-risk actions
- Full audit trail of agent actions

## Depends on

Phase 10.

**Previous:** [Phase 10](../phase-10-non-human-identities/) · **Next:** [Phase 12](../phase-12-entitlement-management/)
