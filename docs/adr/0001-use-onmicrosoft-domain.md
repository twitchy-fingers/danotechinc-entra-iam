# ADR-0001: Use the onmicrosoft.com domain for all identities

- **Status:** Accepted
- **Date:** 2026-10-27
- **Deciders:** Chukwuemeka Eze (CIO), Adaeze Nwosu (IAM Manager)
- **Phase:** 00

## Context
DanotechInc's tenant is `danotechinc.onmicrosoft.com`. A custom domain (`danotechinc.com`) would normally be verified so users sign in with their corporate address. The lab doesn't own that domain.

## Decision
All UPNs, admin accounts and app identifiers use `danotechinc.onmicrosoft.com`. Documentation refers to "danotechinc.com" only as the company's brand.

## Alternatives considered
| Option | Why not chosen |
|---|---|
| Verify `danotechinc.com` | Domain not owned. |
| Verify a different owned domain | Adds DNS management with little learning value for this program. |

## Consequences
- **Email:** No mailboxes exist (no Exchange Online licences). Notifications such as access review emails and alerts go to an external address configured on the action group or to admins' `otherMails`. Each affected phase notes this.
- **SAML apps:** Some SaaS apps (Salesforce, Atlassian) prefer a verified domain for domain claiming. Phase 08 documents the onmicrosoft workaround for each.
- **Migration:** If a custom domain is added later, UPNs can be changed in bulk with the HR feed's UPN mapping. `employeeId` remains the immutable key, so nothing else breaks.
