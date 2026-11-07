# Phase 02 Walkthrough: Identity Source and HR Data Model

**Goal:** Agree the HR-to-Entra attribute contract, prove the HR feed is fit to provision from, prove the quality gate blocks bad data, and confirm the tenant has no clashes, all **before** a single user is created.

**Time:** About 2 hours.
**Performed by:** Adaeze Nwosu (IAM Manager) and Kofi Owusu (Senior IAM Engineer), with Tunde Afolabi (HR Operations Manager) for Steps 2, 3 and 5.

## Prerequisites

- Phase 01 complete (Daniel Opara's daily account has `employeeId = DT01001`).
- **PowerShell 7.2+.** Every command in this walkthrough is PowerShell. The Microsoft Graph module (installed in Phase 01) is used in Step 9.
- **Python 3.10+.** The validator uses only the standard library, so there's nothing to `pip install`. Run it from PowerShell with `python`.

All Python commands run from `phase-02-identity-data-model\scripts\python\`.

---

## Step 1: Get to know the HR feed

**Why:** You can't write rules for data you haven't looked at. Ten minutes reading the file tells you which columns drive access, which ones are free text, and where problems are likely to hide.

Open [`data/hr/employees.csv`](../data/hr/employees.csv) on GitHub (it renders as a searchable table) or in a spreadsheet. Look for:

- **The join key:** `EmployeeId`. Every row has one, in the format `DT01001`–`DT01200`.
- **Free text vs codes:** compare `JobTitle` with `JobCode`. Search for `ENG-EM`: five rows, five different titles, one code. That's why access must key on codes.
- **Lifecycle signals:** sort by `EmploymentStatus` (6 `PreHire`) and filter `EmployeeType` (12 `Contractor`, 4 `Intern`). These rows drive Phase 04's joiner and leaver scenarios.
- **What's missing:** there's no "is a manager" column, even though managers approve access. That gap becomes the derived `IsPeopleManager` attribute.

---

## Step 2: Review and agree the attribute contract

**Why:** The contract is the boundary between HR's responsibilities and IAM's. Without it, each team assumes the other one is checking the data. When a wrong department grants wrong access, nobody owns the fix.

Open [`contract/hr-attribute-contract.json`](contract/hr-attribute-contract.json) and walk through it with Tunde Afolabi. For each field, confirm three things:

| Question | Example |
|---|---|
| **Who is authoritative?** | `JobCode`: HR. `UserPrincipalName`: IAM. |
| **Which Entra ID attribute does it land in?** | `JobCode` → `extensionAttribute1`; `CostCenter` → `employeeOrgData/costCenter` |
| **What makes it valid?** | `EmployeeId` must match `^DT\d{5}$` and be unique; `EmployeeType` must be Employee, Contractor or Intern |

Pay particular attention to:

- **`EmployeeId` is immutable** (`"mutable": false`). HR must never reuse or change one, because it's the only thing tying a person to their account. Changing it would orphan the old account and create a new one.
- **`UserPrincipalName` authority is IAM.** HR may suggest it, but IAM's naming rule decides. This stops HR's system from renaming sign-in names when someone's name changes.
- **The two derived attributes** (`AccountEnabled`, `IsPeopleManager`). Nobody types these; they're calculated. Make sure HR understands that setting `EmploymentStatus` to *Active* is what turns an account on.

In a real organisation, both owners would approve the contract in the pull request (Step 10). That approval is the evidence that HR accepted responsibility for data quality.

---

## Step 3: Review the job code catalogue

**Why:** Phase 03 grants access by job code. If the catalogue is wrong, for example a code listed under the wrong department, every person with that code gets the wrong access. Reference data needs the same scrutiny as the feed itself.

Open [`reference/job-codes.csv`](reference/job-codes.csv). For each of the 73 codes, check with HR:

| Column | What to verify | Why |
|---|---|---|
| `DepartmentCode` | The code belongs to the right department | Department-based access follows it |
| `MinLevel` / `MaxLevel` | Realistic seniority range | Catches level typos (rule DQ-18) |
| `AllowedEmployeeTypes` | Which worker types may hold this code | **Security-critical:** e.g. `FIN-AP` is `Employee` only, so contractors can never be coded into a role with payment rights |
| `ManagerialRole` | Whether the role is normally managerial | Informational; actual management comes from reporting lines |

Spot-check the security-relevant ones: `FIN-AP`, `FIN-PAY`, `HR-HRIS`, `IT-IAM-ENG` and `SEC-SOC-MGR` should all be employee-only. `SEC-SOC` allows contractors, because the SOC uses one, so Phase 03 must handle that carefully.

---

## Step 4: Validate the live HR feed

**Why:** This is the quality gate. If the feed can't pass, Phase 04 can't run. Running it now, weeks before provisioning, gives HR time to fix problems without delaying anyone's start date.

```powershell
cd phase-02-identity-data-model\scripts\python
python validate_hr_feed.py ..\..\..\data\hr\employees.csv --as-of 2026-11-05 --profile `
  --report ..\..\evidence\20261105-hr-feed-validation.md
"Exit code: $LASTEXITCODE"
```

`$LASTEXITCODE` holds the exit code of the last program PowerShell ran. `0` means passed; `1` means blocked.

Use today's date for `--as-of` when you run it yourself (or leave it out; it defaults to today). Results can differ by date, which Step 8 explains.

**Expected result (as of 5 November 2026):** `Errors: 0 · Warnings: 6`, **PASSED**, exit code `0`.

Read the **profile** at the bottom of the report too. It's not a check, but it tells you things later phases need:

- **29 people managers.** These are the access approvers and reviewers in Phases 12 and 13.
- **Largest span of control: Brandon Collins, 16 direct reports.** When quarterly access reviews start, he reviews 16 people's access. That's useful to know before designing review campaigns.
- **20 records with a future end date** (4 leavers, 12 contractors, 4 interns). Each needs a leaver workflow in Phase 04.

---

## Step 5: Act on the warnings

**Why:** Warnings don't block the feed, but they're real problems. If nobody acts on them, they turn into errors or access risks later. Each one gets an owner and an issue.

Open an issue for each finding (template: **Phase task**, milestone **Phase 02 Identity data model**):

| Issue | Owner | Expected outcome |
|---|---|---|
| Confirm Nicole Reed's (DT01101) start; update status from PreHire | Tunde Afolabi | Status set to Active, or start date moved if she hasn't started |
| Contract renewals for 5 contractors over 12 months | Tunde Afolabi, with each contractor's manager | Renewal approved, or end date shortened |

Note how DQ-15 handles Nicole Reed. Her account will be created **disabled** (she's PreHire) and stays disabled until HR confirms. Enabling accounts on the hire date regardless would risk enabling an account for someone whose offer fell through.

---

## Step 6: Prove the gate blocks bad data

**Why:** A control you've only seen pass hasn't been tested. Auditors (and Nana Agyeman in Phase 17) want evidence that the gate **stops** bad data, not just that good data gets through.

[`test-data/employees-with-errors.csv`](test-data/README.md) is a copy of the feed with 13 defects injected, each targeting a different rule.

```powershell
python validate_hr_feed.py ..\..\test-data\employees-with-errors.csv --as-of 2026-11-05 `
  --report ..\..\evidence\20261105-hr-feed-validation-negative-test.md
"Exit code: $LASTEXITCODE"
```

**Expected:** **BLOCKED**, 14 errors, exit code `1`.

Compare the findings with the defect list in [`test-data/README.md`](test-data/README.md). Every injected defect should appear. If one doesn't, the rule has a gap. Three worth looking at:

- **DQ-13** (contractor without end date): without this, a contractor's account would never expire. That's exactly the risk the readiness assessment raised.
- **DQ-09** (reporting loop): two QA engineers set as each other's manager. An approval routed "to the manager" would bounce between them forever.
- **DQ-15** (Active with a passed end date): a leaver HR forgot to process. Provisioning would keep the account enabled.

The non-zero exit code matters: Phase 04's pipeline checks it and refuses to provision.

---

## Step 7: Prove the circuit breaker

**Why:** The most damaging HR data problem isn't a typo. It's a *missing* file, or one that stopped part-way. To a provisioning system, 50 missing rows look exactly like 50 people leaving. The mass-change guard (DQ-21) stops that before any account is disabled.

```powershell
# On its own, the truncated file looks fine
python validate_hr_feed.py ..\..\test-data\employees-truncated.csv --as-of 2026-11-05 |
  Select-Object -First 8

# Compared with the previous good file, it's blocked
python validate_hr_feed.py ..\..\test-data\employees-truncated.csv `
  --previous ..\..\..\data\hr\employees.csv --as-of 2026-11-05 |
  Select-String 'Result|DQ-21'
```

**Expected:** the first run **PASSES**, which is the point: every remaining row is valid. The second run is **BLOCKED**: *50 of 200 records (25%) disappeared… threshold is 10%.*

The 10% threshold is set in the contract (`massChangeThresholdPercent`). It's a business decision, not a technical one: high enough to allow a normal week of leavers, low enough to catch a broken export. Phase 04 configures Entra ID's own **accidental deletion prevention** as a second, independent safety net.

---

## Step 8: See how time changes the result

**Why:** Data quality isn't a one-off check. A record that was correct last week can be wrong today without anyone editing it. Seeing this for yourself explains why the gate runs on every export.

```powershell
python validate_hr_feed.py ..\..\..\data\hr\employees.csv --as-of 2026-10-27 | Select-String 'Errors|DQ-15'
python validate_hr_feed.py ..\..\..\data\hr\employees.csv --as-of 2026-11-30 | Select-String 'Errors|DQ-15'
```

`Select-String` is PowerShell's equivalent of `grep`: it keeps only lines matching the pattern.

- **27 October** (the export date): no DQ-15 findings. Nicole Reed hadn't started yet.
- **30 November:** several **errors**. The four scheduled leavers' end dates (6–27 November) have passed but they're still *Active*, and more pre-hires are past their start dates.

This is exactly what would happen if HR stopped sending updates. The gate blocks, and someone notices, instead of leavers keeping access.

---

## Step 9: Check the tenant is ready

**Why:** The feed being valid isn't enough. It also has to fit the tenant. If an account already exists with a feed UPN but a different `employeeId`, provisioning would fail, or worse, merge two people into one account. Checking now means Phase 04 starts with a known, clean state.

### 9a. Look at the tenant first (portal)

Before running a check, see the tenant with your own eyes. It makes the script's results easy to interpret.

1. [Entra admin center](https://entra.microsoft.com) → **Users → All users**. At this point there should be exactly four accounts: **Daniel Opara**, **ADM - Daniel Opara**, **Emergency Access 01** and **Emergency Access 02**. Anything else is either a test account from earlier experiments or something nobody documented, which is exactly what the readiness check calls an *orphan*.
2. Open **Daniel Opara → Properties**, section **Job information**: **Employee ID = DT01001** (set in Phase 01). That's the value the HR feed will match on.
3. Open **ADM - Daniel Opara → Properties**: the same Employee ID, and **Employee type = AdminAccount**. Same person, different account type.

### 9b. Run the readiness check (script)

The portal shows four accounts; the script checks all 200 HR records against them systematically, which isn't practical by eye.

```powershell
cd ..\powershell
./01-Test-TenantReadiness.ps1            # delegated, as adm.daniel.opara
# or, once Phase 01's automation app is set up:
./01-Test-TenantReadiness.ps1 -AppOnly
```

**Expected results:**

| Check | Expected | Meaning |
|---|---|---|
| 1. Will be adopted | **1**: DT01001 `daniel.opara@` | Phase 01 linked his account; provisioning will update it rather than duplicate it |
| 2. UPN clashes | **0** | No existing account blocks a feed UPN |
| 3. Outside HR control | **0** | Break-glass and `adm.` accounts are recognised as documented exceptions |
| 4. Reserved attributes in use | **0** | `extensionAttribute1`–`4` are free for the data model |
| Ready | **YES** | |

If check 3 lists an account, decide whether it should exist. A test account from earlier experiments should be deleted. A legitimate service account should be documented and, in Phase 10, replaced with a workload identity.

---

## Step 10: Record the decision and commit

**Why:** The attribute model is a decision every later phase depends on. Recording it as an ADR means anyone who later asks "why is JobCode in extensionAttribute1?" gets the answer and the reasoning.

1. Review [ADR-0004](../docs/adr/0004-hr-attribute-model.md) (included in this phase).
2. Check `evidence/` contains:
   - `20261105-hr-feed-validation.md` (positive test)
   - `20261105-hr-feed-validation-negative-test.md` (negative test)
   - `YYYYMMDD-tenant-readiness.json` (from Step 9)
3. Commit on a branch and open a pull request linked to the **Phase 02 Identity data model** milestone. In a real team, Tunde Afolabi (HR) and Adaeze Nwosu (IAM) would both approve it. Their approval is the sign-off on the contract.

## Validation checklist

- [ ] Attribute contract reviewed; authority confirmed for every field
- [ ] Job code catalogue reviewed; security-relevant codes confirmed employee-only
- [ ] Live feed passes with 0 errors; warnings have issues and owners
- [ ] Negative test blocked with exit code 1
- [ ] Truncated file blocked by DQ-21
- [ ] Tenant readiness: 1 adoption, 0 clashes, 0 orphans, 0 attribute conflicts
- [ ] ADR-0004 merged; evidence committed

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `FileNotFoundError` for `departments.csv` | Script run from another folder and the repo layout changed | Keep the repo structure intact; paths are relative to the script's location |
| Accented names look garbled (`RamÃ­rez`) | File re-saved in a non-UTF-8 encoding (often Excel) | Save as **CSV UTF-8**; the validator reads UTF-8 |
| Accented names look wrong only in the PowerShell window | Console decoding Python's UTF-8 output with an older code page | Run `[Console]::OutputEncoding = [Text.Encoding]::UTF8` once in the window. Report files are unaffected |
| Different warning counts from the README | You ran with a different `--as-of` date | Expected. Time-based rules (DQ-11, DQ-15) depend on the date |
| Readiness check shows `Insufficient privileges` | Consent not granted for `User.Read.All` | `Disconnect-MgGraph`, then rerun |
| Readiness check lists the CEO under clashes | Phase 01 Step 8 not done, so `employeeId` is missing | Run Phase 01's `06-Remove-StandingAdminFromDailyAccount.ps1`, which sets it |

**Next:** [Phase 03: RBAC design](../phase-03-rbac-design/)
