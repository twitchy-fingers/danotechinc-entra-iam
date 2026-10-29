# HR Master Data: the DanotechInc Source of Truth

This folder simulates the export from DanotechInc's HR system (think Workday or BambooHR). It is the **only** authoritative source of workforce identity in the project.

That principle matters more than any single file here. In a mature identity program, nobody creates a user account by hand. HR hires a person, the HR record flows to Entra ID, and the account appears with the right attributes, manager and access. When HR terminates someone, the account is disabled automatically. If IT can create accounts outside that flow, you get orphaned accounts, missing managers and access nobody can explain to an auditor.

So in this project, **users are not created in Entra ID until Phase 04**, when the HR feed is wired in through API-driven inbound provisioning. Phases 02 and 03 design the data and the role model first, so the automation has something correct to apply.

## Files

| File | Purpose |
|---|---|
| [`employees.csv`](employees.csv) | 200 workforce records. The HR feed. |
| [`departments.csv`](departments.csv) | Department codes, cost centres, divisions, headcount and department heads. |
| [`org-chart.md`](org-chart.md) | Headcount by office, leadership chart and technology org chart. |
| [`generate_employees.py`](generate_employees.py) | Deterministic generator (fixed seed). Re-running it produces an identical file. |

## Company profile

DanotechInc is a 200-person B2B software company headquartered in Atlanta, with offices in London, Lagos, Accra and Mexico City, plus US remote staff. It sells a SaaS platform, which is why Engineering (54) and Sales (32) are its largest departments.

| Office | Usage location | People |
|---|---|---|
| Atlanta HQ | US | 50 |
| London | GB | 40 |
| Mexico City | MX | 38 |
| Accra | GH | 30 |
| Lagos | NG | 28 |
| Remote - US | US | 14 |

Names reflect each office's population and real-world diaspora, so you will find Nigerian and Ghanaian names in London and Atlanta, and some Indian and Kenyan names among UK and US staff.

## Schema and Entra ID attribute mapping

Each column maps to a specific Entra ID user attribute. This mapping becomes the attribute-mapping configuration of the provisioning app in Phase 04, so it's defined once here and reused.

| CSV column | Entra ID attribute | Why it matters |
|---|---|---|
| `EmployeeId` | `employeeId` | Immutable join key between HR and Entra ID. Never reused, never changes, even if a person's name does. |
| `FirstName` / `LastName` | `givenName` / `surname` | Display and search. |
| `DisplayName` | `displayName` | What people see in apps. |
| `UserPrincipalName` | `userPrincipalName` | Sign-in name. Format `first.last@danotechinc.onmicrosoft.com`; accents stripped, numeric suffix on collision. |
| `MailNickname` | `mailNickname` | Required by Entra ID on user creation. |
| `JobTitle` | `jobTitle` | Shown in apps; also used in some dynamic groups. |
| `JobCode` | `extensionAttribute1` | **Primary RBAC driver.** Dynamic groups in Phase 05 key on job code, not job title, because titles get edited for vanity and codes don't. |
| `JobLevel` | `extensionAttribute2` | L1 (intern) to L10 (CEO). Drives manager-tier access and approval routing. |
| `JobFamily` | `extensionAttribute3` | Groups related job codes (e.g. all Finance roles). |
| `Department` | `department` | Department-wide groups and access reviews. |
| `CostCenter` | `employeeOrgData/costCenter` | Licence charge-back and finance reporting. |
| `Division` | `employeeOrgData/division` | Corporate / Go-To-Market / Technology. |
| `ManagerEmployeeId` | `manager` (reference) | Manager is set by resolving this ID to the manager's object. Managers approve access and run reviews in Phases 12 and 13. |
| `CompanyName` | `companyName` | Distinguishes employees from guests and partner accounts. |
| `Office` / `City` / `Country` | `officeLocation` / `city` / `country` | Location-aware Conditional Access and reporting. |
| `UsageLocation` | `usageLocation` | **Required before a licence can be assigned.** Licensing fails silently without it. |
| `EmployeeType` | `employeeType` | Employee / Contractor / Intern. Contractors and interns get narrower access and mandatory expiry. |
| `EmploymentStatus` | `accountEnabled` (derived) | `PreHire` → created disabled; `Active` → enabled. |
| `HireDate` | `employeeHireDate` | Triggers joiner workflows in Lifecycle Workflows. |
| `EndDate` | `employeeLeaveDateTime` | Triggers leaver workflows. Writing it needs the `User-LifeCycleInfo.ReadWrite.All` permission. |

Why use `extensionAttribute1`–`3` instead of custom directory extensions? They exist on every user object without registering anything, they work in dynamic group rules, and they're writable for cloud-only users. Custom extensions are an option later if we run out.

## Built-in lifecycle scenarios

The feed already contains people in every lifecycle state, so Phase 04 can demonstrate the full joiner–mover–leaver flow against real records. Movers aren't in the master file; Phase 04 introduces them as HR change files (promotions and department transfers) applied on top of it.

| EmployeeId | Name | Title | Department | Type | Status | HireDate | EndDate | JML scenario |
|---|---|---|---|---|---|---|---|---|
| DT01038 | Elikem Agyeman | Accountant Intern | Finance | Intern | Active | 2026-06-01 | 2026-12-18 | Intern, fixed-term |
| DT01043 | Edem Tetteh | Accounts Payable Specialist | Finance | Employee | Active | 2025-07-28 | 2026-11-27 | Leaver (termination scheduled) |
| DT01057 | Nkechi Ogunleye | HR Generalist | Human Resources | Employee | PreHire | 2026-12-07 |  | Joiner (pre-hire, account staged before start) |
| DT01080 | Ebere Bello | Content Strategist | Marketing | Employee | Active | 2019-07-15 | 2026-11-13 | Leaver (termination scheduled) |
| DT01082 | Ashley King | Content Strategist (Contract) | Marketing | Contractor | Active | 2026-02-01 | 2027-02-28 | Contractor with contract end date |
| DT01083 | Bukola Afolabi | Digital Marketing Specialist Intern | Marketing | Intern | Active | 2026-06-01 | 2026-12-18 | Intern, fixed-term |
| DT01087 | José Sánchez | Graphic Designer (Contract) | Marketing | Contractor | Active | 2026-04-01 | 2027-03-28 | Contractor with contract end date |
| DT01089 | Andrés Hernández | Graphic Designer (Contract) | Marketing | Contractor | Active | 2026-02-01 | 2027-04-28 | Contractor with contract end date |
| DT01101 | Nicole Reed | Account Executive | Sales | Employee | PreHire | 2026-11-02 |  | Joiner (pre-hire, account staged before start) |
| DT01102 | Niamh Jones | Account Executive | Sales | Employee | PreHire | 2026-11-09 |  | Joiner (pre-hire, account staged before start) |
| DT01115 | Sofía Reyes | Sales Development Representative | Sales | Employee | Active | 2021-04-19 | 2026-11-06 | Leaver (termination scheduled) |
| DT01126 | Daniela García | Customer Success Manager | Customer Success | Employee | PreHire | 2026-11-30 |  | Joiner (pre-hire, account staged before start) |
| DT01133 | Chiamaka Okafor | Support Engineer (Contract) | Customer Success | Contractor | Active | 2026-07-01 | 2027-02-28 | Contractor with contract end date |
| DT01144 | Valeria Morales | Senior Software Engineer | Engineering | Employee | PreHire | 2026-11-16 |  | Joiner (pre-hire, account staged before start) |
| DT01145 | Efua Appiah | Software Engineer (Contract) | Engineering | Contractor | Active | 2026-07-01 | 2027-01-28 | Contractor with contract end date |
| DT01146 | Yetunde Afolabi | Software Engineer (Contract) | Engineering | Contractor | Active | 2026-07-01 | 2027-01-28 | Contractor with contract end date |
| DT01147 | Halima Akinola | Software Engineer (Contract) | Engineering | Contractor | Active | 2026-08-01 | 2027-05-28 | Contractor with contract end date |
| DT01148 | Nii Amoah | Software Engineer Intern | Engineering | Intern | Active | 2026-06-01 | 2026-12-18 | Intern, fixed-term |
| DT01154 | Valeria Castillo | Software Engineer (Contract) | Engineering | Contractor | Active | 2026-01-01 | 2027-01-28 | Contractor with contract end date |
| DT01155 | Danielle Brown | Software Engineer Intern | Engineering | Intern | Active | 2026-06-01 | 2026-12-18 | Intern, fixed-term |
| DT01157 | María Castillo | Software Engineer | Engineering | Employee | Active | 2024-04-15 | 2026-11-20 | Leaver (termination scheduled) |
| DT01169 | Sanjay Kapoor | Data Engineer | Engineering | Employee | PreHire | 2027-01-04 |  | Joiner (pre-hire, account staged before start) |
| DT01174 | Selorm Amoah | QA Engineer (Contract) | Engineering | Contractor | Active | 2026-07-01 | 2027-04-28 | Contractor with contract end date |
| DT01177 | Akua Quaye | QA Engineer (Contract) | Engineering | Contractor | Active | 2026-03-01 | 2027-02-28 | Contractor with contract end date |
| DT01192 | Aisha Okonkwo | Service Desk Analyst (Contract) | Information Technology | Contractor | Active | 2026-02-01 | 2027-05-28 | Contractor with contract end date |
| DT01196 | Musa Afolabi | SOC Analyst (Contract) | Information Security | Contractor | Active | 2026-04-01 | 2027-05-28 | Contractor with contract end date |

## Key personas

These people recur across phases as admins, approvers, reviewers and test subjects. Full list in [`org-chart.md`](org-chart.md).

| Person | Role | Recurring responsibility |
|---|---|---|
| Daniel Opara | CEO | Executive sponsor. Holds the original Global Admin account, which Phase 01 removes from daily use. |
| Chukwuemeka Eze | CIO | Accountable owner of the identity platform. |
| Oliver Hughes | CISO | Owns security policy and Conditional Access standards; approves privileged access. |
| Adaeze Nwosu | IAM Manager | Project lead. Approves IAM changes. |
| Kofi Owusu, Diego Ramírez, Emily Carter | IAM Engineers | Build and operate the platform. |
| Babatunde Bakare | Cloud & Infrastructure Manager | Owns Azure subscriptions (Phases 01, 09, 10). |
| Grace Robinson | Service Desk Lead | Tier-1 user support; scoped helpdesk admin rights. |
| Priya Sharma | Security Operations Manager | Owns monitoring, detections and risk response (Phases 14, 15). |
| Nana Agyeman | GRC Manager | Owns access reviews, audit evidence and compliance mapping (Phases 13, 17). |
| Folasade Adeyemi, Tunde Afolabi | CPO, HR Operations Manager | Own the HR feed and data quality. |
| Fernanda Castillo | Sales Operations Manager | Salesforce business owner (Phase 08). |
| Ngozi Balogun | Director of Digital Marketing | WordPress business owner (Phase 08). |
| Carlos Gutiérrez | Engineering Manager, DevOps & SRE | GitHub and CI/CD owner (Phases 08, 10). |
