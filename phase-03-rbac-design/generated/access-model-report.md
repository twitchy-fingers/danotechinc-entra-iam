# Access model simulation report

- Evaluated as of: 2026-11-05
- People: 200 · Roles: 58 (Birthright 1, Department 11, Job 29, Privileged 12, Requestable 5) · Entitlements: 59
- Active people (counted in role sizes): 194 · Pre-hires (roles apply from day one): 6
- Entitlement grants: 1427 (average 7.1 per person, max 15)
- Grants by sensitivity: Low 882, Medium 439, High 72, Privileged 34
- Errors: **0** · Warnings: **0**
- Result: **PASS: model is ready to implement**

## Policy checks

| Check | Description | Result |
|---|---|---|
| PC-01 | Every job code maps to a job role | ✅ Pass |
| PC-02 | Everyone receives birthright access | ✅ Pass |
| PC-03 | Roles reference real entitlements; everything has an owner | ✅ Pass |
| PC-04 | Privileged entitlements only through PIM roles | ✅ Pass |
| PC-05 | Contractors and interns never receive High or Privileged access | ✅ Pass |
| PC-06 | Privileged role members are active employees | ✅ Pass |
| PC-07 | Requestable roles have no automatic membership | ✅ Pass |
| PC-08 | Every entitlement is granted by some role | ✅ Pass |
| PC-09 | Every role has members | ✅ Pass |
| SOD | No one holds both sides of a SoD rule without an approved exception | ✅ Pass |

## Separation of duties

| Rule | Person | Side A held | Side B held | Status |
|---|---|---|---|---|
| SOD-01 | Rachel Okafor (DT01022) | EXP-APPROVER | EXP-FIN-PAY | Excepted (EXC-001, expires 2027-05-05) |

### Conflicts that Phase 12 must block at request time

These people don't hold a conflict today, but could **request** the other side through an access package. Phase 12 configures these packages as incompatible.

| Rule | Requestable role | People who must be blocked |
|---|---|---|
| SOD-02 | `RQ-GH-REPO-ADMIN` | 7 |

## Role sizes

| Role | Layer | Group | Members |
|---|---|---|---|
| `BR-WORKFORCE` | Birthright | `GRP-DYN-ALL-Workforce` | 194 |
| `DR-EXE` | Department | `GRP-DYN-DEPT-Executive` | 3 |
| `DR-FIN` | Department | `GRP-DYN-DEPT-Finance` | 18 |
| `DR-HR` | Department | `GRP-DYN-DEPT-HumanResources` | 11 |
| `DR-LEG` | Department | `GRP-DYN-DEPT-Legal` | 7 |
| `DR-OPS` | Department | `GRP-DYN-DEPT-Operations` | 10 |
| `DR-MKT` | Department | `GRP-DYN-DEPT-Marketing` | 22 |
| `DR-SAL` | Department | `GRP-DYN-DEPT-Sales` | 30 |
| `DR-CS` | Department | `GRP-DYN-DEPT-CustomerSuccess` | 15 |
| `DR-ENG` | Department | `GRP-DYN-DEPT-Engineering` | 52 |
| `DR-IT` | Department | `GRP-DYN-DEPT-IT` | 16 |
| `DR-SEC` | Department | `GRP-DYN-DEPT-Security` | 9 |
| `JR-EXEC-OFFICE` | Job | `GRP-DYN-JOB-EXEC-OFFICE` | 3 |
| `JR-EXEC-INSIGHT` | Job | `GRP-DYN-JOB-EXEC-INSIGHT` | 3 |
| `JR-FIN-AP` | Job | `GRP-DYN-JOB-FIN-AP` | 4 |
| `JR-FIN-ACCOUNTING` | Job | `GRP-DYN-JOB-FIN-ACCOUNTING` | 7 |
| `JR-FIN-CONTROLLER` | Job | `GRP-DYN-JOB-FIN-CONTROLLER` | 1 |
| `JR-FIN-FPA` | Job | `GRP-DYN-JOB-FIN-FPA` | 4 |
| `JR-FIN-PAYROLL` | Job | `GRP-DYN-JOB-FIN-PAYROLL` | 2 |
| `JR-HR-PEOPLE` | Job | `GRP-DYN-JOB-HR-PEOPLE` | 11 |
| `JR-HR-HRIS` | Job | `GRP-DYN-JOB-HR-HRIS` | 2 |
| `JR-LEGAL` | Job | `GRP-DYN-JOB-LEGAL` | 7 |
| `JR-LEGAL-COMPLIANCE` | Job | `GRP-DYN-JOB-LEGAL-COMPLIANCE` | 4 |
| `JR-OPS` | Job | `GRP-DYN-JOB-OPS` | 10 |
| `JR-MKT` | Job | `GRP-DYN-JOB-MKT` | 22 |
| `JR-MKT-WEB` | Job | `GRP-DYN-JOB-MKT-WEB` | 4 |
| `JR-SAL-SELLER` | Job | `GRP-DYN-JOB-SAL-SELLER` | 23 |
| `JR-SAL-LEADER` | Job | `GRP-DYN-JOB-SAL-LEADER` | 7 |
| `JR-CS` | Job | `GRP-DYN-JOB-CS` | 15 |
| `JR-ENG-DEV` | Job | `GRP-DYN-JOB-ENG-DEV` | 32 |
| `JR-ENG-PLATFORM` | Job | `GRP-DYN-JOB-ENG-PLATFORM` | 7 |
| `JR-ENG-DATA` | Job | `GRP-DYN-JOB-ENG-DATA` | 6 |
| `JR-ENG-PRODUCT` | Job | `GRP-DYN-JOB-ENG-PRODUCT` | 7 |
| `JR-IT-LEADER` | Job | `GRP-DYN-JOB-IT-LEADER` | 1 |
| `JR-IT-IAM` | Job | `GRP-DYN-JOB-IT-IAM` | 4 |
| `JR-IT-CLOUD` | Job | `GRP-DYN-JOB-IT-CLOUD` | 6 |
| `JR-IT-SERVICEDESK` | Job | `GRP-DYN-JOB-IT-SERVICEDESK` | 5 |
| `JR-SEC-SOC` | Job | `GRP-DYN-JOB-SEC-SOC` | 5 |
| `JR-SEC-SOC-LIMITED` | Job | `GRP-DYN-JOB-SEC-SOC-LIMITED` | 1 |
| `JR-SEC-GRC` | Job | `GRP-DYN-JOB-SEC-GRC` | 4 |
| `JR-PEOPLE-MANAGER` | Job | `GRP-DYN-JOB-PeopleManagers` | 29 |
| `PR-GLOBAL-ADMIN` | Privileged | `GRP-ROLE-PIM-GLOBAL-ADMIN` | 1 |
| `PR-PRIV-ROLE-ADMIN` | Privileged | `GRP-ROLE-PIM-PRIV-ROLE-ADMIN` | 1 |
| `PR-IAM-ADMIN` | Privileged | `GRP-ROLE-PIM-IAM-ADMIN` | 4 |
| `PR-HELPDESK` | Privileged | `GRP-ROLE-PIM-HELPDESK` | 4 |
| `PR-SEC-OPERATOR` | Privileged | `GRP-ROLE-PIM-SEC-OPERATOR` | 2 |
| `PR-SF-ADMIN` | Privileged | `GRP-ROLE-PIM-SF-ADMIN` | 2 |
| `PR-GH-OWNER` | Privileged | `GRP-ROLE-PIM-GH-OWNER` | 2 |
| `PR-WP-ADMIN` | Privileged | `GRP-ROLE-PIM-WP-ADMIN` | 2 |
| `PR-ATL-ADMIN` | Privileged | `GRP-ROLE-PIM-ATL-ADMIN` | 1 |
| `PR-KC-ADMIN` | Privileged | `GRP-ROLE-PIM-KC-ADMIN` | 1 |
| `PR-AZ-OWNER` | Privileged | `GRP-ROLE-PIM-AZ-OWNER` | 1 |
| `PR-LOG-ADMIN` | Privileged | `GRP-ROLE-PIM-LOG-ADMIN` | 1 |
| `RQ-GH-REPO-ADMIN` | Requestable | `GRP-AP-GH-REPO-ADMIN` | on request |
| `RQ-AZ-PROD-READER` | Requestable | `GRP-AP-AZ-PROD-READER` | on request |
| `RQ-EXP-AUDITOR` | Requestable | `GRP-AP-EXP-AUDITOR` | on request |
| `RQ-CONF-SPACE-FIN` | Requestable | `GRP-AP-CONF-SPACE-FIN` | on request |
| `RQ-SF-READONLY` | Requestable | `GRP-AP-SF-READONLY` | on request |

## Sample personas

### Rachel Okafor (DT01022): Financial Controller, Finance

*Financial Controller: the only approved SoD exception (EXC-001).*

Roles: `BR-WORKFORCE`, `DR-FIN`, `JR-FIN-CONTROLLER`, `JR-PEOPLE-MANAGER`

| Entitlement | Application | Sensitivity | Via |
|---|---|---|---|
| CONF-SPACE-FIN | Atlassian Cloud | Medium | DR-FIN |
| CONF-USER | Atlassian Cloud | Low | BR-WORKFORCE |
| EXP-APPROVER | Danotech Expenses | Medium | JR-PEOPLE-MANAGER |
| EXP-FIN-PAY | Danotech Expenses | High | JR-FIN-CONTROLLER |
| EXP-FIN-REVIEW | Danotech Expenses | Medium | JR-FIN-CONTROLLER |
| EXP-SUBMITTER | Danotech Expenses | Low | BR-WORKFORCE |
| JIRA-BUSINESS | Atlassian Cloud | Low | JR-FIN-CONTROLLER |
| JSM-PORTAL | Atlassian Cloud | Low | BR-WORKFORCE |
| SF-READONLY | Salesforce | Medium | JR-FIN-CONTROLLER |

### Carlos Castillo (DT01159): DevOps Engineer, Engineering

*DevOps engineer: production deploy rights, so must never get repository admin (SOD-02).*

Roles: `BR-WORKFORCE`, `DR-ENG`, `JR-ENG-PLATFORM`

| Entitlement | Application | Sensitivity | Via |
|---|---|---|---|
| AZ-DEV-CONTRIB | Azure | Medium | JR-ENG-PLATFORM |
| AZ-PROD-DEPLOY | Azure | High | JR-ENG-PLATFORM |
| AZ-PROD-READER | Azure | Medium | JR-ENG-PLATFORM |
| CONF-SPACE-ENG | Atlassian Cloud | Medium | DR-ENG |
| CONF-USER | Atlassian Cloud | Low | BR-WORKFORCE |
| EXP-SUBMITTER | Danotech Expenses | Low | BR-WORKFORCE |
| GH-MEMBER | GitHub | Low | JR-ENG-PLATFORM |
| GH-TEAM-PLATFORM | GitHub | Medium | JR-ENG-PLATFORM |
| JIRA-SW-USER | Atlassian Cloud | Low | JR-ENG-PLATFORM |
| JSM-PORTAL | Atlassian Cloud | Low | BR-WORKFORCE |

### Musa Afolabi (DT01196): SOC Analyst (Contract), Information Security

*SOC contractor: gets the limited SOC role, not Security Reader, because contractors can't hold High access.*

Roles: `BR-WORKFORCE`, `JR-SEC-SOC-LIMITED`

| Entitlement | Application | Sensitivity | Via |
|---|---|---|---|
| AZ-LOG-READER | Azure | Medium | JR-SEC-SOC-LIMITED |
| CONF-USER | Atlassian Cloud | Low | BR-WORKFORCE |
| EXP-SUBMITTER | Danotech Expenses | Low | BR-WORKFORCE |
| JIRA-SM-AGENT | Atlassian Cloud | Low | JR-SEC-SOC-LIMITED |
| JSM-PORTAL | Atlassian Cloud | Low | BR-WORKFORCE |

### Nii Amoah (DT01148): Software Engineer Intern, Engineering

*Software engineering intern: same job role as engineers, nothing High.*

Roles: `BR-WORKFORCE`, `DR-ENG`, `JR-ENG-DEV`

| Entitlement | Application | Sensitivity | Via |
|---|---|---|---|
| AZ-DEV-CONTRIB | Azure | Medium | JR-ENG-DEV |
| CONF-SPACE-ENG | Atlassian Cloud | Medium | DR-ENG |
| CONF-USER | Atlassian Cloud | Low | BR-WORKFORCE |
| EXP-SUBMITTER | Danotech Expenses | Low | BR-WORKFORCE |
| GH-MEMBER | GitHub | Low | JR-ENG-DEV |
| GH-TEAM-ENG | GitHub | Medium | JR-ENG-DEV |
| JIRA-SW-USER | Atlassian Cloud | Low | JR-ENG-DEV |
| JSM-PORTAL | Atlassian Cloud | Low | BR-WORKFORCE |

### Kofi Owusu (DT01015): Senior IAM Engineer, Information Technology

*Senior IAM engineer: standing Global Reader, plus PIM-eligible admin roles.*

Roles: `BR-WORKFORCE`, `DR-IT`, `JR-IT-IAM`, `PR-IAM-ADMIN`, `PR-SF-ADMIN`, `PR-KC-ADMIN`

| Entitlement | Application | Sensitivity | Via |
|---|---|---|---|
| AZ-LOG-READER | Azure | Medium | JR-IT-IAM |
| CONF-SPACE-IT | Atlassian Cloud | Medium | DR-IT |
| CONF-USER | Atlassian Cloud | Low | BR-WORKFORCE |
| ENTRA-APP-ADMIN | Microsoft Entra ID | Privileged | PR-IAM-ADMIN |
| ENTRA-CA-ADMIN | Microsoft Entra ID | Privileged | PR-IAM-ADMIN |
| ENTRA-GLOBAL-READER | Microsoft Entra ID | High | JR-IT-IAM |
| ENTRA-IG-ADMIN | Microsoft Entra ID | Privileged | PR-IAM-ADMIN |
| ENTRA-USER-ADMIN | Microsoft Entra ID | Privileged | PR-IAM-ADMIN |
| EXP-SUBMITTER | Danotech Expenses | Low | BR-WORKFORCE |
| GH-MEMBER | GitHub | Low | JR-IT-IAM |
| JIRA-SM-AGENT | Atlassian Cloud | Low | JR-IT-IAM |
| JSM-PORTAL | Atlassian Cloud | Low | BR-WORKFORCE |
| KC-REALM-ADMIN | Keycloak Partner Portal | Privileged | PR-KC-ADMIN |
| SF-ADMIN | Salesforce | Privileged | PR-SF-ADMIN |

### Nicole Reed (DT01101): Account Executive, Sales

*Pre-hire: roles are calculated now but only take effect when HR activates the account (groups require accountEnabled = true).*

Roles: `BR-WORKFORCE`, `DR-SAL`, `JR-SAL-SELLER`

| Entitlement | Application | Sensitivity | Via |
|---|---|---|---|
| CONF-SPACE-SAL | Atlassian Cloud | Medium | DR-SAL |
| CONF-USER | Atlassian Cloud | Low | BR-WORKFORCE |
| EXP-SUBMITTER | Danotech Expenses | Low | BR-WORKFORCE |
| JSM-PORTAL | Atlassian Cloud | Low | BR-WORKFORCE |
| SF-SALES-USER | Salesforce | Medium | JR-SAL-SELLER |
