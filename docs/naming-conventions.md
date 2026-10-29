# DanotechInc Naming Conventions

Names are the cheapest control in identity. A consistent name tells an admin, an auditor or a KQL query what an object is, who owns it and how risky it is, without opening it. Every phase follows this standard. Changes require an ADR in [`docs/adr`](adr/).

## Accounts

| Object | Pattern | Example | Notes |
|---|---|---|---|
| Workforce user | `first.last@danotechinc.onmicrosoft.com` | `adaeze.nwosu@…` | Created only by the HR feed (Phase 04). Accents stripped; numeric suffix on collision (`jose.garcia2`). |
| Admin account | `adm.first.last@danotechinc.onmicrosoft.com` | `adm.kofi.owusu@…` | Separate from the daily account. No mailbox, no app access, no licence beyond Entra ID P2. Display name `ADM - Kofi Owusu`. |
| Break-glass account | `bg-<random>-01@danotechinc.onmicrosoft.com` | `bg-k7q2-01@…` | Not tied to a person. A random token makes it harder to guess from a staff list. Display name `Emergency Access 01`. |
| Guest | Set by B2B invitation | `user_partner.com#EXT#@…` | Managed through entitlement management (Phase 12). |
| Service / test account | `svc-<purpose>@…` | `svc-saml-test@…` | Avoided where a workload identity can be used instead (Phase 10). |

## Groups

`GRP-<Type>-<Scope>-<Purpose>`

| Type | Meaning | Example |
|---|---|---|
| `DYN` | Dynamic membership, rule-driven from HR attributes | `GRP-DYN-DEPT-Finance` |
| `ASG` | Assigned membership, owned by a named person | `GRP-ASG-APP-Salesforce-Admins` |
| `ROLE` | Role-assignable group (can hold Entra roles) | `GRP-ROLE-PIM-HelpdeskAdmins` |
| `CA` | Used only for Conditional Access targeting or exclusions | `GRP-CA-Exclude-BreakGlass` |
| `LIC` | Group-based licensing | `GRP-LIC-EntraP2` |
| `AP` | Created by an access package | `GRP-AP-Finance-ERP-ReadOnly` |

Scope values: `DEPT`, `JOB`, `LOC`, `APP`, `PIM`, `AZ` (Azure RBAC), `ALL`.

## Conditional Access policies

`CA<NNN>-<Persona>-<Apps>-<Control>`

Numbers are grouped by persona so the policy list sorts into readable blocks:

| Range | Persona |
|---|---|
| CA000–CA099 | Global / all users |
| CA100–CA199 | Admins |
| CA200–CA299 | Internal workforce |
| CA300–CA399 | Guests and external users |
| CA400–CA499 | Workload identities |
| CA900–CA999 | Temporary or break-fix policies (must have an expiry noted in the description) |

Example: `CA100-Admins-AllApps-RequireMFA`.

## Applications

| Object | Pattern | Example |
|---|---|---|
| Enterprise app (SaaS) | `<Vendor> - <Purpose>` | `Salesforce - SSO` |
| App registration (internal) | `app-danotech-<purpose>` | `app-danotech-iam-automation` |
| API exposed by Danotech | `api-danotech-<name>` | `api-danotech-ticketing-tool` |
| AI agent identity | `agent-danotech-<name>` | `agent-danotech-helpdesk` |

## Azure resources

`<type>-danotech-<workload>-<env>-<region>` following the Microsoft Cloud Adoption Framework abbreviations.

| Resource | Example |
|---|---|
| Resource group | `rg-danotech-identity-prd-eus` |
| Log Analytics workspace | `log-danotech-identity-prd-eus` |
| Managed identity | `id-danotech-<workload>-prd` |
| Key Vault | `kv-danotech-iam-prd-eus` |

## Repository artefacts

| Artefact | Pattern |
|---|---|
| Phase folder | `phase-NN-<kebab-name>` |
| PowerShell script | `NN-Verb-Noun.ps1` (approved PowerShell verbs) |
| Python script | `snake_case.py` |
| Evidence file | `YYYYMMDD-<what>.json` or `.png` |
| ADR | `docs/adr/NNNN-<kebab-title>.md` |
