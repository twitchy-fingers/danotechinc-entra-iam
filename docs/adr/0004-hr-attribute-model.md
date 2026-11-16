# ADR-0004: HR attribute model, join key and reserved extension attributes

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Adaeze Nwosu (IAM Manager), Tunde Afolabi (HR Operations Manager), Folasade Adeyemi (CPO)
- **Phase:** 02

## Context
Phase 03 grants access from HR attributes, and Phase 04 provisions accounts from the HR feed. Both need a stable way to match records to accounts and stable attributes to key access on. Job titles are free text and vary (five Engineering Managers have five titles). The HR feed has no field saying who manages people.

## Decision
1. **`EmployeeId` is the immutable join key** between HR and Entra ID (`employeeId`). It is never reused or changed. Admin accounts carry the same `employeeId` with `employeeType = AdminAccount`.
2. **Access keys on codes, not titles.** Four `extensionAttribute`s are reserved:

   | Attribute | Holds | Source |
   |---|---|---|
   | `extensionAttribute1` | JobCode | HR |
   | `extensionAttribute2` | JobLevel | HR |
   | `extensionAttribute3` | JobFamily | HR |
   | `extensionAttribute4` | `PeopleManager` or `IndividualContributor` | Derived from reporting lines (never empty, so it can be updated by provisioning) |
3. **HR is authoritative** for all person attributes; **IAM** generates the UPN once and derives `accountEnabled` and `IsPeopleManager`.
4. **Every HR file passes `validate_hr_feed.py`** before provisioning. Any ERROR, including the 10% mass-change guard, blocks the run.

## Alternatives considered
| Option | Why not chosen |
|---|---|
| Match on UPN or email | Derived from names, which change; would duplicate accounts on name change. |
| Key access on `jobTitle` | Free text; every title variant needs a new rule. |
| Custom directory extensions (`extension_<appId>_jobCode`) | Need an app registration to own them and are more verbose in dynamic rules. Kept as an option if more than 15 attributes are ever needed. |
| Derive "manager" from job level | Wrong both ways: some L6 staff manage teams, others don't. |

## Consequences
- `extensionAttribute1`–`4` must not be used for anything else. The Phase 02 readiness check flags any existing use.
- Changing a person's job code changes their access automatically (Phase 05), so job code changes in HR become access changes. HR must treat them with care.
- Rehires reuse their `EmployeeId`, so their old account is reactivated, not duplicated.
