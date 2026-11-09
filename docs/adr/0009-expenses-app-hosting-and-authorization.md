# ADR-0009: Danotech Expenses hosting and authorization model

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Adaeze Nwosu (IAM Manager), Emily Carter (IAM Engineer), Rachel Okafor (business owner)
- **Phase:** 05

## Context
Phase 05 needs a working OIDC application to demonstrate app roles and to enforce the Phase 03 separation-of-duties rules, including the compensating control for exception EXC-001. It should be demonstrable to others, not only on one PC.

## Decision
1. **Host on Azure App Service (Linux, F1 free tier)**, created in the Azure portal and developed and tested on localhost first. One app registration serves both, with two redirect URIs.
2. **Deploy from GitHub through Deployment Center** with a **user-assigned managed identity** (GitHub OIDC federation, no deployment password), from a `release/expenses` branch, because the `main` ruleset (Phase 00) rejects the direct commit Deployment Center makes. A release is a merge from `main`.
3. **Python (Flask + MSAL)**, authorization code flow with PKCE. The ID token identifies the user and carries app roles; the access token (Graph `User.Read`) is used once to read the manager and never stored.
4. **Authorization comes only from app roles**, assigned to the Phase 05 dynamic groups. The app registration, its roles and the first assignment are built in the portal; the remaining assignments are derived from the Phase 03 entitlements (`EXP-*`) by script, which also verifies the portal configuration. Assignment required is on.
5. **Separation of duties is enforced server-side**, and every denial is written to an activity log readable by `Expenses.Audit` holders.
6. **A 30-day client secret** is accepted temporarily, stored only in a file outside the repository and in App Service settings. **Phase 10 replaces it with the App Service managed identity** (no secret).

## Alternatives considered
| Option | Why not chosen |
|---|---|
| Localhost only | Can't be shown to others; no real HTTPS redirect URI or platform-held settings. |
| Deploy with Azure CLI from a PC | Works, but nothing links the running code to a commit, and it needs a person's credentials. |
| Deployment Center with basic authentication (publish profile) | A long-lived deployment password stored in GitHub; exactly the pattern finding F-07 is about. |
| Exempt Deployment Center from the `main` ruleset | Weakens the protection every other change relies on. |
| App Service Easy Auth (built-in authentication) | Hides the OIDC flow the phase is meant to demonstrate. |
| Token inspection with jwt.ms only | Shows a token, but no authorization decisions or SoD enforcement. |
| Certificate credential now | Loading private certificates isn't available on the free tier; the managed identity route in Phase 10 is better anyway. |
| Group claims instead of app roles | Group IDs in tokens leak directory structure and break when groups are recreated; app roles are named, app-specific and stable. |

## Consequences
- The client secret is a known, time-limited weakness, tracked until Phase 10.
- The `release/expenses` branch isn't covered by the `main` ruleset; in a team it would get its own ruleset allowing only merges from `main`.
- F1 apps sleep when idle; first requests are slow. Acceptable for a demonstration.
- The app's SQLite database lives on App Service storage; it's demonstration data, not a system of record.
