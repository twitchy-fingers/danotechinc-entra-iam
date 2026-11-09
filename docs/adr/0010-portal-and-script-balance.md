# ADR-0010: Portal for one-off setup, scripts for bulk and repeatable work

- **Status:** Accepted. Applies from Phase 02 onwards; amends the tooling approach in [ADR-0003](0003-msgraph-powershell-primary.md).
- **Date:** 2026-11-05
- **Deciders:** Adaeze Nwosu (IAM Manager), Kofi Owusu (Senior IAM Engineer)
- **Phase:** Program-level

## Context
Phases 00–01 were almost entirely scripted. Real IAM teams work in both the Entra admin center and the Azure portal and in automation; a program that only shows scripts doesn't show where settings live or how they look to the people who review them. But doing bulk work by hand is slow and error-prone, and manual changes can drift from the design.

## Decision
1. **Portal** for one-off settings and for the **first item of a kind**: a policy, the first group, the first workflow, an app registration, Azure resources, reviewing logs and histories.
2. **Scripts** for **bulk and repeatable** work: creating many similar objects, daily operations, reconciliation, and evidence exports.
3. **Scripts verify portal work.** When an item is built by hand, the script that builds the rest of its kind compares it with the design and reports or repairs differences (for example: WF-02 against its JSON; `GRP-DYN-ALL-Workforce` against the model; the Expenses app registration against its checklist).
4. **Evidence from the portal** is captured as screenshots in each phase's `evidence/` folder; evidence from scripts as exported files.

## Applied in Phases 02–05
| Phase | Portal | Script |
|---|---|---|
| 02 | First look at existing users and Daniel's employee ID | HR validation; tenant readiness check |
| 03 | Inspect built-in role permissions to justify sensitivity ratings | Role model simulation |
| 04 | Provisioning app and mappings; TAP policy; upload permission; workflow settings; WF-02; on-demand runs; logs and workflow history | Feed upload; reconciliation; four workflows; manager addresses; bulk TAPs; evidence |
| 05 | First group; licensing group (bulk import); app registration, roles, consent, secret; first role assignment; App Service; Deployment Center | 40 groups; membership proof; 8 role assignments; local run; evidence |

## Consequences
- Walkthroughs mix portal steps and commands; each step says which it is.
- Portal menu names change between releases, so walkthroughs name the setting as well as the path.
- Manual work is never trusted unverified: every hand-built item has a scripted check.
