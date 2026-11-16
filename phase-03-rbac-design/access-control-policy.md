# DanotechInc Access Control Policy

| Field | Value |
|---|---|
| Policy ID | POL-IAM-001 |
| Version | 1.0 |
| Owner | Oliver Hughes, Chief Information Security Officer |
| Maintained by | Adaeze Nwosu, IAM Manager |
| Approved by | Oliver Hughes (CISO), Chukwuemeka Eze (CIO) |
| Effective | 2026-11-05 |
| Review cycle | Annually, or after any significant change to the role model |

## 1. Purpose

This policy sets the rules for how access to DanotechInc's systems and data is granted, changed, reviewed and removed. It applies the principle of **least privilege**: every identity gets only the access its job requires, for only as long as it requires it.

## 2. Scope

All DanotechInc workforce identities (employees, contractors and interns), administrator accounts, guests, workload identities and AI agents, and all systems in the application inventory: Microsoft Entra ID, Azure, Salesforce, Atlassian Cloud, GitHub, WordPress, the Keycloak partner portal, Danotech Expenses and the HR system.

## 3. Definitions

| Term | Meaning |
|---|---|
| **Entitlement** | A single permission in a system, such as the Salesforce *Sales User* profile or the Azure *Reader* role. |
| **Role** | A named bundle of entitlements that a group of people need for the same work. |
| **Birthright access** | Access everyone in a population receives automatically. |
| **Sensitivity** | How much damage misuse of an entitlement could cause: Low, Medium, High or Privileged (section 6). |
| **Role owner** | The person accountable for what a role contains and who holds it. |
| **SoD conflict** | Two entitlements that, held together, would let one person complete a sensitive action without a check by anyone else. |

## 4. Policy statements

### Granting access

**AC-01. Access is role-based.** Access is granted through roles defined in the DanotechInc role model, not to individuals directly. Direct assignment of an entitlement to a person is prohibited, except for documented break-glass accounts.

**AC-02. Roles are driven by HR data.** Birthright, department and job roles are assigned automatically from HR attributes (department, job code, employee type, people-manager status). Job **titles** must not be used to grant access.

**AC-03. Default deny.** Access not granted by a role is denied. No entitlement is granted "just in case".

**AC-04. Additional access is requested and approved.** Access beyond a person's roles must be requested through an access package with approval by the person's manager **and** the role or resource owner, and must have an expiry date (implemented in Phase 12).

**AC-05. No access before start or after end.** Accounts are created disabled before the hire date and gain role-based access only when HR confirms the start. Access is removed when employment ends (implemented in Phase 04).

### Fixed-term workers

**AC-06. Contractors and interns never receive High or Privileged access automatically.** Roles that grant High or Privileged entitlements are restricted to employees. A contractor who needs such access requires a time-limited, approved request with CISO sign-off.

**AC-07. Contractors and interns may not hold administrator roles.** Privileged roles are restricted to employees.

**AC-08. Fixed-term access ends with the contract.** Contractor and intern accounts must carry an end date. Contracts longer than 12 months require renewal approval for access to continue.

### Privileged access

**AC-09. Privileged access is just-in-time.** Privileged entitlements are granted only through PIM-eligible roles that must be activated with justification and expire automatically (implemented in Phase 06). Standing privileged access is permitted only for the two break-glass accounts.

**AC-10. Separate administrator accounts.** Privileged roles are assigned to dedicated `adm.` accounts, never to a person's daily account.

### Separation of duties

**AC-11. SoD conflicts are prohibited.** No person may hold both sides of a separation-of-duties rule. Current rules are listed in [`model/sod-rules.csv`](model/sod-rules.csv).

**AC-12. Exceptions are rare, approved and time-limited.** An SoD exception requires a business justification, a compensating control, approval by the business owner **and** the CISO, and an expiry date no more than 6 months away. Exceptions are recorded in [`model/sod-exceptions.csv`](model/sod-exceptions.csv) and re-approved at expiry.

**AC-13. Conflicts are checked before access is granted.** Every change to the role model is simulated before deployment, and the access request process (Phase 12) blocks requests that would create a conflict.

### Ownership and review

**AC-14. Every role and entitlement has a named owner.** Owners approve requests and review access to what they own.

**AC-15. Access is reviewed.** Privileged roles, guests and High-sensitivity access are reviewed quarterly; other access annually (implemented in Phase 13).

**AC-16. The role model is controlled by change management.** Changes to roles, entitlements, SoD rules or exceptions are made through a reviewed pull request, and the simulation must pass before merge.

## 5. Role layers

| Layer | Assignment | Example | Who approves changes to the role |
|---|---|---|---|
| Birthright | Automatic, all workforce | `BR-WORKFORCE` | IAM Manager |
| Department | Automatic, by department | `DR-FIN` | Department head |
| Job | Automatic, by job code or people-manager status | `JR-FIN-AP` | Role owner |
| Privileged | Named members, PIM-eligible | `PR-IAM-ADMIN` | CISO |
| Requestable | Access package, approval and expiry | `RQ-GH-REPO-ADMIN` | Role owner |

## 6. Sensitivity levels

| Level | Definition | Examples | Controls |
|---|---|---|---|
| **Low** | Collaboration and self-service; misuse has minimal impact | Confluence, submit own expenses | Birthright allowed |
| **Medium** | Business data access within a team's normal work | Salesforce user, non-production Azure | Role-based; contractors allowed |
| **High** | Sensitive data or changes with financial or production impact | Release payments, HR records, production deploy | Employees only; quarterly review |
| **Privileged** | Administrative control of a system | Global Administrator, Salesforce admin | PIM only; `adm.` accounts; quarterly review |

## 7. Compliance

Breaches of this policy are handled through DanotechInc's disciplinary process. Technical controls enforcing this policy are mapped to frameworks in Phase 17; the primary mappings are ISO/IEC 27001:2022 Annex A 5.3 (segregation of duties), 5.15 (access control), 5.18 (access rights) and 8.2 (privileged access rights), SOC 2 CC6.1–CC6.3, and NIST CSF 2.0 PR.AA.
