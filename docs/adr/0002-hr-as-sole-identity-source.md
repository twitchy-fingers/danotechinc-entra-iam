# ADR-0002: HR is the sole source of workforce identities

- **Status:** Accepted
- **Date:** 2026-10-27
- **Deciders:** Chukwuemeka Eze (CIO), Folasade Adeyemi (CPO), Adaeze Nwosu (IAM Manager)
- **Phase:** 00

## Context
Manually created accounts are the most common source of orphaned, over-privileged and unexplained access.

## Decision
Workforce accounts are created, updated and disabled only by the HR-driven provisioning pipeline (Phase 04). The only accounts created by hand are break-glass accounts, admin accounts (Phase 06 automates these too) and explicitly documented test or service accounts.

## Alternatives considered
| Option | Why not chosen |
|---|---|
| Bulk-create 200 users with a script in Phase 01 | Fast, but it teaches the wrong pattern and bypasses the JML controls we're building. |
| IT creates accounts on HR request tickets | Manual, slow and error-prone; no single source of truth. |

## Consequences
Phases 01–03 run with only a handful of accounts. That is intentional: the tenant is hardened and the role model is designed before 200 people arrive.
