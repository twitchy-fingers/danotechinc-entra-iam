# Phase 03 Walkthrough: RBAC Design

**Goal:** Agree the access control policy, build and review the entitlement and role catalogues, simulate the model against all 200 people, prove the simulation catches violations, and hand Phase 05 a tested set of dynamic group rules.

**Time:** About 3 hours, more if you involve real department heads in the reviews.
**Performed by:** Adaeze Nwosu (IAM Manager) and Kofi Owusu (Senior IAM Engineer), with Oliver Hughes (CISO) for Steps 1 and 11, and application owners for Step 6.

## Prerequisites

- Phase 02 complete (the job code catalogue in `phase-02-identity-data-model/reference/job-codes.csv` is used here).
- **PowerShell 7.2+.** Every command here is PowerShell.
- **Python 3.10+.** Standard library only; nothing to `pip install`.
- A text editor or spreadsheet for the CSV files (see the note in Troubleshooting about Excel).

All commands run from `phase-03-rbac-design\` in PowerShell.

> **Nothing in this phase touches the tenant.** That's deliberate. RBAC mistakes are cheap to fix in a CSV and expensive to fix once dynamic groups are pushing access into six applications.

---

## Step 1: Agree the access control policy first

**Why:** The policy is the yardstick the model is measured against. If you design roles first, the policy tends to get written to describe whatever the roles happen to do. Agreeing the rules first ("contractors never get High access", "no one approves and pays") means the roles have to meet them, not the other way round.

Read [`access-control-policy.md`](access-control-policy.md) with Oliver Hughes. Focus on the statements the simulation enforces automatically:

| Statement | Enforced by simulation check |
|---|---|
| AC-01 Access is role-based | Every grant traces to a role (`GrantedByRoles` column) |
| AC-02 Roles driven by HR data, never titles | Roles only use department, job code, level, type, manager |
| AC-06 Contractors/interns never get High or Privileged automatically | PC-05 |
| AC-07 Contractors/interns never hold admin roles | PC-06 |
| AC-09 Privileged access only through PIM roles | PC-04 |
| AC-11/12 No SoD conflicts without an approved, unexpired exception | SOD |
| AC-14 Every role and entitlement has an owner | PC-03 |

Also agree the **sensitivity levels** (policy section 6). They decide which controls apply to each entitlement, so a disagreement here changes the whole model.

---

## Step 2: Review the entitlement catalogue (bottom-up)

**Why:** Roles are bundles of entitlements, so the entitlements have to be right first. The catalogue is also the first place DanotechInc has ever listed, in one place, every meaningful permission it hands out. Auditors call this the *entitlement inventory*.

Open [`model/entitlements.csv`](model/entitlements.csv). For each row, check:

| Column | What to check | Why it matters |
|---|---|---|
| `Sensitivity` | Is it rated by the damage misuse could cause? | Drives PC-05 (contractors), PIM (Privileged) and review frequency |
| `Owner` | Is it the **business** owner, not the person who configures it? | Owners approve requests and review access |
| `GrantedBy` | Which mechanism and phase delivers it? | Confirms every entitlement can actually be implemented |

Some ratings worth discussing, because they're judgement calls:

- **`EXP-FIN-PAY` is High; `EXP-FIN-REVIEW` is Medium.** Reviewing a claim can't move money; releasing a payment can.
- **`ENTRA-GLOBAL-READER` is High, not Privileged.** It can't change anything, but it can read the entire directory configuration, which is exactly what an attacker wants for reconnaissance. So it's employees-only, but it can be standing rather than PIM.
- **`AZ-LOG-CONTRIB` is Privileged.** It sounds harmless, but it can delete log data, which makes it an evidence-destruction risk (SOD-04).
- **`CONF-SPACE-HR` is High while `CONF-SPACE-MKT` is Low.** Same entitlement type, very different content.

### Check a rating against the real permissions (portal)

Sensitivity ratings should come from what a permission actually allows, not from its name. For the Entra ID entitlements you can see this directly:

1. [Entra admin center](https://entra.microsoft.com) → **Entra ID → Roles & admins → All roles** → search **Helpdesk Administrator** → open it → **Description**.
2. Read the permission list. It includes resetting passwords and invalidating sessions for non-administrators. Anyone holding it can take over most user accounts, which is why `ENTRA-HELPDESK-ADMIN` is rated **Privileged** and will only ever be granted just-in-time (Phase 06).
3. Do the same for **Global Reader**: every permission ends in `read`. It can't change anything, which is why `ENTRA-GLOBAL-READER` is **High** (sensitive reconnaissance value) rather than **Privileged**.
4. Open **Assignments** on either role: nobody holds them yet. That's expected; Phase 06 creates the admin accounts and eligible assignments.

---

## Step 3: Understand how roles are defined

**Why:** You'll edit this file in Steps 7 and 8, and every future access change goes through it. Knowing exactly how a row becomes group membership avoids surprises.

Open [`model/roles.csv`](model/roles.csv). Each row is one role; the criteria columns decide who gets it:

| Column | Example | Matches |
|---|---|---|
| `Departments` | `FIN` | People whose department code is FIN |
| `JobCodes` | `ENG-DEVOPS\|ENG-SRE` | People with **either** code (`\|` means OR) |
| `JobLevels` | `L7\|L8` | People at either level (unused today, available) |
| `EmployeeTypes` | `Employee` | Only employees, not contractors or interns |
| `PeopleManager` | `Yes` | Only people with direct reports |
| `Members` | `DT01015\|DT01016` | Privileged roles only: named employees |
| `Entitlements` | `SF-SALES-USER;JIRA-BUSINESS` | What the role grants (`;` separates entitlements) |

**Criteria combine with AND**; values inside one criterion combine with OR. So `JR-ENG-PLATFORM` means *job code is ENG-DEVOPS **or** ENG-SRE, **and** employee type is Employee*. Empty criteria match everyone.

Look at the pair `JR-SEC-SOC` and `JR-SEC-SOC-LIMITED`. They share the job code `SEC-SOC` but differ in `EmployeeTypes`. That's how one job can be split by worker type when policy requires it.

---

## Step 4: Run the simulation

**Why:** Reading 58 roles can't tell you what 200 people end up with. The simulation applies every role to every person in the HR feed, exactly as dynamic groups will in Phase 05, and checks the result against the policy.

```powershell
python scripts\python\build_access_model.py --as-of 2026-11-05
"Exit code: $LASTEXITCODE"
```

**Expected:** `Errors: 0 · Warnings: 0`, **PASS**, exit code `0`. The script writes five files to `generated/`.

Copy the report into evidence:

```powershell
Copy-Item generated\access-model-report.md "evidence\$(Get-Date -Format yyyyMMdd)-access-model-simulation.md"
```

---

## Step 5: Read the simulation report

**Why:** A PASS tells you no rule is broken. The rest of the report tells you whether the model is *sensible*, which no automated check can judge.

Open [`generated/access-model-report.md`](generated/access-model-report.md) and work through it:

1. **Headline numbers.** 1,427 grants, average 7.1 per person. If a change ever doubles the average, that's access creep. **Privileged: 34 grants** held by 14 named people; that number should only fall over time.
2. **Separation of duties.** One row: Rachel Okafor, SOD-01, *Excepted (EXC-001)*. Confirm that's the only one.
3. **Conflicts to block at request time.** SOD-02, `RQ-GH-REPO-ADMIN`, 7 people. Write this down: it becomes a configuration item in Phase 12.
4. **Role sizes.** Look for surprises. `JR-PEOPLE-MANAGER` has 29 members, which matches the Phase 02 profile. `JR-SEC-SOC-LIMITED` has 1 (Musa Afolabi). A role with hundreds of members outside the birthright layer would deserve a second look.
5. **Sample personas.** Read each one and ask: *would this person's manager agree this is what they need?*

---

## Step 6: Have owners review the permission matrix

**Why:** IAM designs the model, but owners are accountable for it (policy AC-14). An owner who has reviewed and agreed their system's access before it goes live can't later say "nobody asked me". Their approval is also the first piece of access-review evidence.

Open [`generated/permission-matrix.md`](generated/permission-matrix.md). It has one table per system, showing which roles grant which entitlements, and how many people hold each role.

Walk each owner through their table:

| System | Owner | Questions to ask |
|---|---|---|
| Danotech Expenses | Rachel Okafor | Should 4 FP&A staff (including the CFO) have auditor read access to every claim? |
| Salesforce | Fernanda Castillo | Is read-only enough for Finance? Should Product Managers see Salesforce at all? |
| GitHub | Carlos Gutiérrez | Should Cloud Engineers (IT) write to platform repos alongside DevOps? |
| Azure | Babatunde Bakare | Is production read for all 7 DevOps/SRE engineers right? |
| HR system | Tunde Afolabi | Is HRIS-READ for every HR team member too broad? |

Record each owner's approval as a comment on the pull request (Step 11), or as a change to the model if they disagree. If they ask for a change, edit `model/roles.csv`, rerun Step 4, and show them the new matrix.

---

## Step 7: Exercise: break separation of duties on purpose

**Why:** A control that has only ever passed hasn't been tested. This exercise proves the simulation catches the kind of change that, in real life, arrives as an innocent-looking request: *"Can DevOps have repo admin? It'd save us a ticket every time we update branch protection."*

1. Open `model/roles.csv` and find the `JR-ENG-PLATFORM` row.
2. Add `;GH-REPO-ADMIN` to the end of its `Entitlements` value, so it ends `…;AZ-PROD-DEPLOY;GH-REPO-ADMIN`.
3. Run the simulation, writing output somewhere temporary:

   ```powershell
   python scripts\python\build_access_model.py --as-of 2026-11-05 --out "$env:TEMP\sim"
   ```

   `--out "$env:TEMP\sim"` writes the results to your temporary folder, so the real `generated\` files aren't overwritten by a deliberately broken model.

**Expected:** **FAIL** with **8 errors**:
- one *role-level* error: `JR-ENG-PLATFORM grants both sides by itself`, a design flaw regardless of who's in the role;
- seven *person-level* errors, one for each DevOps and SRE engineer.

4. **Undo the change** (remove `;GH-REPO-ADMIN`) and rerun Step 4 to confirm it passes again.

The right answer to the DevOps request is what the model already does: repository admin is a requestable, time-limited package (`RQ-GH-REPO-ADMIN`), and Phase 12 blocks it for anyone with production deploy rights. Someone **without** deploy rights updates branch protection.

---

## Step 8: Exercise: give a contractor too much

**Why:** The most common way contractor restrictions fail isn't a deliberate decision. It's someone "simplifying" two roles into one. This exercise shows the policy check catching it.

1. In `model/roles.csv`, find the `JR-SEC-SOC` row and change `EmployeeTypes` from `Employee` to `Employee|Contractor`.
2. Run the simulation to `$env:TEMP\sim` as above.

**Expected:** **FAIL**, 1 error: `PC-05: Contractor Musa Afolabi gets High ENTRA-SEC-READER via JR-SEC-SOC`.

3. **Undo the change** and rerun Step 4.

That's why the SOC has two roles. Musa can still do his job: he reads logs in Log Analytics and works tickets. He just can't browse every security setting in the tenant, which a contractor working for another company doesn't need to do.

---

## Step 9: See an exception expire

**Why:** Exceptions that never expire become permanent policy by accident. EXC-001 has an expiry date, and the simulation enforces it. This step shows what happens when nobody remembers to renew it.

```powershell
python scripts\python\build_access_model.py --as-of 2027-06-01 --out "$env:TEMP\sim"
```

**Expected:** **FAIL**, 1 error: `SOD-01: Rachel Okafor's exception EXC-001 expired 2027-05-05`.

When that happens for real, there are three outcomes:

| Outcome | What to change |
|---|---|
| Renew | Kwame Asante and Oliver Hughes re-approve; update `Expires` in `sod-exceptions.csv` |
| Remove the conflict | Remove `EXP-FIN-PAY` from `JR-FIN-CONTROLLER`, and appoint a different backup releaser |
| Restructure | Move Rachel's direct reports' approvals to someone else |

Add a reminder now: an issue in the **Phase 13 Access reviews** milestone titled *"Re-approve EXC-001 before 2027-05-05"*.

---

## Step 10: Inspect the hand-off to Phase 05

**Why:** Phase 05 builds the groups. If what it builds doesn't match what was simulated here, the simulation proved nothing. Generating the rules from the same data guarantees they match.

Open [`generated/dynamic-group-rules.json`](generated/dynamic-group-rules.json). For each dynamic role you'll see the group name, the expected member count and an Entra ID membership rule, for example `JR-FIN-AP`:

```text
(user.accountEnabled -eq true) -and (user.companyName -eq "DanotechInc")
  -and (user.extensionAttribute1 -in ["FIN-AP"]) -and (user.employeeType -in ["Employee"])
```

Every rule includes two guard conditions:

| Condition | Why |
|---|---|
| `user.accountEnabled -eq true` | Pre-hires (disabled) and leavers (disabled) automatically drop out of every role. No access before day one or after the last day. |
| `user.companyName -eq "DanotechInc"` | Guests and external accounts can never match a workforce role, even if someone sets a matching job code on them. |

`expectedMembers` is the number of **active** people the role should contain. In Phase 05, each group's real member count is compared with this number: a mismatch means HR data, provisioning or the rule is wrong.

Privileged roles appear as *Assigned (role-assignable, PIM-eligible)* with named members, and requestable roles as *Access package*. Those are built in Phases 06 and 12.

---

## Step 11: Record the design and get sign-off

**Why:** This model decides who can do what across the company. It needs the same formal approval as the policy it implements, and a record of why it's shaped this way.

1. Review [ADR-0005](../docs/adr/0005-layered-rbac-model.md) (included in this phase).
2. Check `evidence/` contains the dated simulation report.
3. Commit on a branch and open a pull request linked to the **Phase 03 RBAC design** milestone, including:
   - the policy (approved by Oliver Hughes, CISO, and Chukwuemeka Eze, CIO),
   - the model files and generated outputs,
   - owners' approvals from Step 6 as PR comments.

Label the PR `decision`. Changing the role model later follows policy AC-16: edit the CSVs, rerun the simulation, and the PR can't merge unless it passes.

## Validation checklist

- [ ] Access control policy approved by the CISO and CIO
- [ ] Entitlement sensitivities and owners reviewed
- [ ] Simulation passes: 0 errors, 0 warnings
- [ ] Only SoD finding is EXC-001, unexpired
- [ ] Owners reviewed their permission matrix tables
- [ ] SoD exercise produced 8 errors, then was reverted
- [ ] Contractor exercise produced PC-05, then was reverted
- [ ] Exception expiry demonstrated; renewal reminder issue created
- [ ] `dynamic-group-rules.json` reviewed; guard conditions understood
- [ ] ADR-0005 merged; evidence committed

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Names show as `RamÃ­rez` after editing a CSV | Saved in a non-UTF-8 encoding | In Excel use **Save As → CSV UTF-8**. A plain text editor (VS Code) avoids the problem |
| Excel changes `L10` or IDs into other formats | Excel auto-formatting | Edit the CSVs in a text editor, or import them with all columns as Text |
| `KeyError` mentioning a column | A header was renamed or a column deleted | Restore the header row from Git |
| `PC-03 … references unknown entitlement` | Typo in an entitlement ID, or `,` used instead of `;` | Entitlements are separated by `;`; criteria values by `\|` |
| Simulation passes but an exercise didn't fail | Edit didn't save, or edited the wrong row | Check with `git diff model/roles.csv`, or reopen the file |
| Accented names look wrong only in the PowerShell window (`RamÃ­rez`) | The console is decoding Python's UTF-8 output with an older code page | Run `[Console]::OutputEncoding = [Text.Encoding]::UTF8` once in the window. The files written to `generated\` are unaffected |
| Exercises left `generated/` changed | Ran without `--out "$env:TEMP\sim"` | Rerun Step 4 with no `--out` to regenerate the real outputs |

**Next:** [Phase 04: JML lifecycle automation](../phase-04-jml-lifecycle/)
