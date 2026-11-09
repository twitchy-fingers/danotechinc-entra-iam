# Phase 04 Walkthrough: JML Lifecycle Automation

**Goal:** Connect the HR feed to Entra ID through API-driven inbound provisioning, deploy joiner/mover/leaver workflows, load all 200 people, then operate the feed daily through the live HR events of 9–20 November.

**Time:** About 4 hours of setup (Part A, finished by **8 November**), then about 15 minutes a day (Part B).
**Performed by:** Kofi Owusu (Senior IAM Engineer) and Adaeze Nwosu (IAM Manager), with Tunde Afolabi (HR) for the HR changes.

> **Hard deadline inside this phase:** the workflows must be deployed **before 9 November**. A time-based workflow doesn't fire for anyone whose hire date is earlier than the workflow's creation date, so deploying on the 9th or later would miss Niamh Jones.

## Prerequisites

- **Phase 01 complete:** break-glass accounts, `adm.daniel.opara`, the automation app with its certificate, and the environment variables `DANOTECH_AUTOMATION_CLIENT_ID` and `DANOTECH_AUTOMATION_CERT_THUMBPRINT` set in your PowerShell session.
- **Phases 02 and 03 run:** the validator passes on the HR file.
- **PowerShell 7.2+** with the Graph module, and **Python 3.10+** on your PATH (`python --version`).
- An external email inbox you own (Outlook.com or Gmail), for workflow notifications.

All commands are PowerShell, run from `phase-04-jml-lifecycle\scripts\powershell\` unless stated.

**Portal or script?** One-off setup happens in the [Entra admin center](https://entra.microsoft.com), so you learn where each setting lives. Bulk and repeatable work is scripted. Where you build the first item of a kind by hand (workflow WF-02), the script that builds the rest also checks your portal work against the definition ([ADR-0010](../docs/adr/0010-portal-and-script-balance.md)). Portal menu names can shift slightly between releases; if a path doesn't match exactly, use the admin center's search box.

## Overview

| Part | Step | Where | When | What |
|---|---|---|---|---|
| A | 1 | Script | Now | Dry run: see exactly what would be sent |
| A | 2–4 | Portal | Now | Create and configure the provisioning app |
| A | 5 | Portal + script | Now | Tenant prerequisites; save the endpoint |
| A | 6 | Portal + script | **By 8 Nov** | Build WF-02 by hand; deploy and check the rest |
| A | 7 | Script + portal | 7 Nov | First load (199 accounts); read the provisioning logs |
| A | 8 | Script | 7 Nov | Route manager notifications to your inbox |
| A | 9 | Script | 7–8 Nov | Rehearse a blocked feed |
| B | 10 | Script + portal | 9–20 Nov | Daily feed and live JML events |
| B | 11 | Script | 19 Nov | Evidence and commit |

---

# Part A: Setup

## Step 1: Dry run the feed

**Why:** Before anything touches Entra ID, look at exactly what would be sent. A dry run builds the snapshot, runs the quality gate and writes the SCIM payloads to files, then stops. If a mapping or transform is wrong, you see it here, in a file, rather than on 200 accounts.

```powershell
cd phase-04-jml-lifecycle\scripts\powershell
./03-Invoke-HrFeedUpload.ps1 -AsOf 2026-11-07 -DryRun
```

**Expected:**
- Snapshot: 200 records, 1 change applied (CHG-001, Sofía Reyes terminated).
- Gate: 0 errors, 6 warnings, PASSED.
- **199 records to send (193 active, 6 inactive), 1 skipped**: Sofía Reyes, *terminated and has no account*.
- 4 batch files in `phase-04-jml-lifecycle\output\scim-20261107\` (50 + 50 + 50 + 49).

Open `batch-01.json`. The first record is Daniel Opara (the only person with no manager), then his direct reports. That's the **managers first** ordering: when a report is created, their manager already exists, so the manager reference resolves on the first pass.

Search a later batch for `DT01102` (Niamh Jones). Note `"active": false`. She's still PreHire on 7 November, so her account will exist but stay disabled until HR confirms her start.

---

## Step 2: Create the API-driven provisioning app

**Why:** The provisioning app is the receiving end of the feed. It owns the `/bulkUpload` endpoint, the attribute mappings and the provisioning logs. Each HR source gets its own app, so a problem with one source can be paused without affecting others.

1. [Entra admin center](https://entra.microsoft.com) as `adm.daniel.opara` → **Enterprise apps → New application**.
2. Search **API-driven provisioning to Microsoft Entra ID** → select it.
3. Name: `DanotechInc HR Inbound Provisioning` → **Create**.
4. In the new app: **Provisioning → Get started** (or **Connect your application**) → **Provisioning mode: Automatic** → **Save**.

Leave provisioning **off** for now. It's turned on in Step 4, after the mappings are correct.

---

## Step 3: Add DanotechInc's attributes and configure mappings

**Why:** Out of the box, the app understands standard SCIM attributes (name, title, department, manager). DanotechInc's access model depends on attributes SCIM doesn't define: job code, job level, people-manager status. They're sent in a custom SCIM extension, and this step teaches the app about them and maps every attribute to its Entra ID destination, exactly as the [Phase 02 contract](../phase-02-identity-data-model/contract/hr-attribute-contract.json) defines.

### 3a. Extend the attribute list

1. **Provisioning → Mappings** → select **Provision API urn:ietf:params:scim:schemas:core:2.0:User**.
2. Tick **Show advanced options** → **Edit attribute list for API**.
3. Add these 10 attributes, all type **String**:

```text
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:JobCode
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:JobLevel
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:JobFamily
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:PeopleManager
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:EmployeeType
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:UsageLocation
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:Office
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:MailNickname
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:HireDate
urn:ietf:params:scim:schemas:extension:danotech:1.0:User:LeaveDate
```

4. **Save**.

### 3b. Configure the mappings

Back on the mapping page, edit or add mappings so they match the [README mapping table](README.md#attribute-mappings). The ones that need care:

| Mapping | Setting | Why |
|---|---|---|
| `externalId` → `employeeId` | **Match objects using this attribute: Yes**, precedence **1** | The join key. Existing accounts are updated, never duplicated |
| `userName` → `userPrincipalName` | **Apply this mapping: Only during object creation** | The contract says UPNs aren't regenerated on a name change |
| `…danotech…:MailNickname` → `mailNickname` | **Only during object creation** | Same reason |
| `…danotech…:JobCode` → `extensionAttribute1` (and `JobLevel` → `2`, `JobFamily` → `3`, `PeopleManager` → `4`) | Always | These drive every dynamic group in Phase 05 |
| `…danotech…:HireDate` → `employeeHireDate` and `LeaveDate` → `employeeLeaveDateTime` | Always | Lifecycle Workflow triggers |
| `urn:…enterprise:2.0:User:manager.value` → `manager` | Always | Resolved by the manager's employeeId |

Remove any default mapping for an attribute that DanotechInc doesn't send (for example phone numbers). An unmapped source left in place can clear the target value.

**Save**, then take a screenshot of the mapping list for `evidence\`.

---

## Step 4: Set the safety threshold and start provisioning

**Why:** The quality gate (DQ-21) is the first safety net against mass disablement. The provisioning service's own **accidental deletion prevention** is the second, and it's independent: it catches a bug in the transform or a bad mapping that the HR data check couldn't see.

1. **Provisioning → Settings**:
   - **Notification email:** your external inbox. Tick *Send an email notification when a failure occurs*.
   - **Prevent accidental deletion:** on. **Accidental deletion threshold: 20** (10% of 200).
   - **Scope:** Sync all users.
2. **Provisioning Status: On** → **Save**.

---

## Step 5: Set the tenant prerequisites (portal)

**Why:** Four one-off settings have to be in place before the first upload. Each is a single decision you make once, so it's done in the portal, where you can see the options and their defaults. Take a screenshot of each for `evidence\`.

### 5a. Enable Temporary Access Pass

Joiners get a TAP instead of a password. A TAP that could be reused would effectively be a password, so it's one-time only.

1. **Entra ID → Authentication methods → Policies → Temporary Access Pass**.
2. **Enable and Target:** Enable **on**, target **All users**.
3. **Configure:** minimum lifetime **1 hour**, maximum lifetime **2 days**, default lifetime **1 day**, **One-time use: Yes**, length **12**.
4. **Save**.

### 5b. Give the automation app its upload permission

Phase 01 created `app-danotech-iam-automation` read-only on purpose. This is its first write permission, granted deliberately and with admin consent, so it shows up in the audit log as an explicit decision.

1. **Entra ID → App registrations → All applications → app-danotech-iam-automation → API permissions**.
2. **Add a permission → Microsoft Graph → Application permissions** → search `SynchronizationData-User.Upload` → tick it → **Add permissions**.
3. **Grant admin consent for DanotechInc → Yes**. The status column turns green.

Notice what the permission does **not** allow: creating or editing users directly. It only allows posting data to the provisioning endpoint, where the mappings, matching rules and accidental deletion threshold still apply.

### 5c. Workflow schedule

1. **ID Governance → Lifecycle workflows → Workflow settings**.
2. **Workflow schedule:** **1** hour (the default is 3). Faster results in the lab; production usually keeps the default.
3. **Save**.

### 5d. Save the provisioning endpoint

1. **Enterprise apps → DanotechInc HR Inbound Provisioning → Provisioning → Overview** (or **View technical information**). Copy the **Provisioning API Endpoint**.
2. Save it for the upload script, which also checks the job is running:

```powershell
./01-Save-ProvisioningTarget.ps1 -Endpoint '<paste the endpoint>'
```

**Expected:** the app name, `Job status: Active`, and `Saved to config\provisioning-target.local.json` (git-ignored).

The automation app's new permission can take a few minutes to reach its tokens. Open a new PowerShell session before Step 7.

---

## Step 6: Build the workflows (by 8 November)

**Why:** Workflows are what happen *around* the account: the TAP on day one, the manager's heads-up, the disable after the last day. You build the first one by hand to learn how a workflow is put together (trigger, scope, tasks). The other four are deployed from JSON in Git, and the same script checks your hand-built one against its definition, so a mistake in the portal can't slip through unnoticed.

### 6a. Build WF-02 in the portal

1. **ID Governance → Lifecycle workflows → Create workflow** → choose the **Onboard new hire employee** template → **Select**.
2. **Basics:**
   - **Name:** `WF-02 Joiner - day one Temporary Access Pass` (exact, so the script recognises it)
   - **Description:** *On the hire date, generate a one-time TAP and email it to the joiner's manager.*
   - **Trigger type:** Time-based attribute. **Days from event: 0**. **Event user attribute: employeeHireDate**.
3. **Configure scope:** **Rule based** → property `companyName`, operator **Equals**, value `DanotechInc`. This keeps guests and admin accounts out.
4. **Review tasks:** the template adds its own tasks. **Remove all of them**, in particular *Enable user account*. HR status, through the feed, decides when an account is enabled, never the calendar ([ADR-0008](../docs/adr/0008-jml-automation-design.md)). Then **Add task → Generate Temporary Access Pass and send via email to user's manager** → in its settings set the lifetime to **1440** minutes (24 hours) and **One-time use: Yes**.
5. **Review + create:** tick **Enable schedule** → **Create**.

### 6b. Deploy the rest and check WF-02

```powershell
./02-Deploy-LifecycleWorkflows.ps1
```

**Expected:**
- `Exists, matches definition: WF-02 …` (your portal work checked against `WF-02-Joiner-Day-One.json`)
- `Created:` WF-01, WF-03, WF-04 and WF-05
- `evidence\YYYYMMDD-lifecycle-workflows.json` written

If WF-02 shows `DIFFERS from definition`, the script lists exactly what's different, for example `unexpected task 'Enable User Account'` or `offset is 1 days, expected 0`. Fix it in the portal (**workflow → Properties** or **Tasks**) and rerun until it matches.

If a task name in the JSON doesn't match Microsoft's current name, the script prints the list of available task names and stops; correct the `taskName` and rerun. If WF-03's mover trigger isn't accepted through the API, build it in the portal from the **Employee job profile change** template (trigger attributes *department* and *jobTitle*, task *Send email to notify manager of user move*), then rerun the script: it will check that one too.

**Check:** **Lifecycle workflows → Workflows** lists five workflows, all with scheduling enabled.

---

## Step 7: First load (7 November)

**Why:** This is the moment 199 accounts appear, every one of them from a validated HR record. Daniel Opara's existing account is adopted rather than duplicated, because Phase 01 stamped `DT01001` on it.

```powershell
./03-Invoke-HrFeedUpload.ps1 -AsOf 2026-11-07
```

**Expected:** gate PASSED, `1 HR-linked accounts already exist` (Daniel), 199 records sent in 4 batches, each `HTTP 202`.

Wait 10 minutes, then check what the provisioning service actually did:

```powershell
./04-Get-ProvisioningResults.ps1 -Since (Get-Date).AddMinutes(-30) -AsOf 2026-11-07
"Exit code: $LASTEXITCODE"
```

**Expected:**
- Provisioning log: about 198 **create** and 1 **update** (Daniel), all **success**.
- Reconciliation: *Entra ID matches HR*, exit code `0`.

If some reports show *manager not set*, their manager was created in the same cycle. Run Step 7's upload once more: it's idempotent, and the second pass resolves the references.

**Read one provisioning log entry in the portal.** The script summarises; the portal shows how the provisioning service reasons about a single record:

1. **Enterprise apps → DanotechInc HR Inbound Provisioning → Provisioning logs**.
2. Open the entry for **Daniel Opara** → **Steps** tab. You'll see *Import* (the SCIM record received), *Match* (found an existing user by `employeeId = DT01001`), *Determine action* (**Update**, not Create) and *Provision*. That's the adoption designed in Phase 01, confirmed.
3. Open any other entry: its *Determine action* is **Create**.

**Spot-check in the portal:** **Users →** search `Niamh` → **Account enabled: No**, **Employee hire date: 9 Nov 2026**, **Manager: Brandon Collins**. Then **Users →** search `Sofía`: no result, as intended.


---

## Step 8: Route manager notifications to your inbox (lab only)

**Why:** Lifecycle Workflows email the manager's `mail` attribute. DanotechInc has no mailboxes, so this lab step points every people manager's `mail` at a plus-address of your inbox. You see every TAP and notice exactly as the manager would, and the `+name` tells you which manager it was for.

```powershell
./05-Set-LabManagerNotificationMail.ps1 -Inbox you@outlook.com -AsOf 2026-11-07
```

**Expected:** 29 managers set, for example `Brandon Collins -> you+brandon.collins@outlook.com`.

If Entra ID rejects an external address, the script stops after the first attempt. In that case, issue each joiner's TAP **in the portal** on their start day: **Users → the joiner → Authentication methods → Add authentication method → Temporary Access Pass**, one-time use, then copy it. It's the same one-time TAP the workflow would have generated.

---

## Step 9: Rehearse a blocked feed

**Why:** On 14 November the feed depends on HR having terminated Ebere Bello. If HR forgets, her account must not stay enabled because of a missing record. Rehearse that failure now, so you recognise it if it happens for real.

From `phase-04-jml-lifecycle\scripts\python\`:

```powershell
Get-Content ..\..\hr-changes\hr-changes.csv | Where-Object { $_ -notmatch '^CHG-007' } |
  Set-Content "$env:TEMP\changes-without-chg007.csv" -Encoding utf8
python build_hr_snapshot.py --as-of 2026-11-14 --changes "$env:TEMP\changes-without-chg007.csv" --out "$env:TEMP\s14.csv"
python ..\..\..\phase-02-identity-data-model\scripts\python\validate_hr_feed.py "$env:TEMP\s14.csv" --as-of 2026-11-14 |
  Select-String 'Result|DQ-15'
```

**Expected:** `BLOCKED`, `DQ-15 … DT01080 Active but EndDate 2026-11-13 has passed: leaver not processed`.

In production the run stops, an issue goes to HR, and WF-04 disables Ebere anyway at its next run. Two independent controls, so one missed step doesn't leave access open.

---

# Part B: Daily operations (9–20 November)

## Step 10: Run the feed each day and verify the live events

**Why:** This is the steady state: HR changes their system, the feed runs, Entra ID follows, and workflows handle the human side. Each day's events are real evidence for the licence-window deadline.

Each morning, run the feed with that day's date, then check results ten minutes later:

```powershell
$day = Get-Date -Format 'yyyy-MM-dd'     # or the schedule date you're catching up on
./03-Invoke-HrFeedUpload.ps1 -AsOf $day
Start-Sleep -Seconds 600
./04-Get-ProvisioningResults.ps1 -Since (Get-Date).AddMinutes(-15) -AsOf $day
```

**Check workflow results in the portal** whenever a workflow should have run: **Lifecycle workflows → the workflow → Workflow history**. *Users summary* shows who was processed, *Runs* shows each scheduled or on-demand run, and *Tasks* shows each task's outcome per person. Step 11 exports the same data as evidence.

If you miss a day, run the missed date first. The snapshot for any date includes every change up to that date, and the mass-change guard compares each run with the one before.

| Date | Feed result (expected) | What to verify |
|---|---|---|
| **9 Nov** | 199 sent: 195 active, 4 inactive. Niamh Jones and Nicole Reed **enabled** | **WF-02** emails Niamh's TAP to `you+brandon.collins@…` within about an hour. **WF-01** emails Valeria Morales's manager (her start is 7 days away). **Nicole Reed** gets no automatic TAP (her hire date predates WF-02), so run it on demand **in the portal**: **Lifecycle workflows → WF-02 → Run on demand → Add users → Nicole Reed → Run workflow** |
| 9 Nov | | **Play the joiner:** private browser window → <https://aka.ms/mysecurityinfo> → sign in as `niamh.jones@…` with the TAP → add **Passkey in Microsoft Authenticator**. Then sign out and back in with the passkey. No password was ever involved |
| **10 Nov** | Miguel Hernández updated: department Finance, job code `FIN-FPA`, manager Kwame Asante | **WF-03** emails `you+kwame.asante@…`. In Phase 05, his group memberships follow the new job code |
| 11 Nov | Gate warnings drop from 5 to 3 (two contracts renewed) | Aisha Okonkwo's and Musa Afolabi's leave dates updated |
| 12–13 Nov | No changes; Ebere Bello still enabled through her last day (13th) | |
| **14 Nov** | 199 sent: Ebere Bello `active: false` | **WF-04** runs for Ebere: account disabled, sessions revoked, email to her manager |
| **16 Nov** | Valeria Morales enabled; Danielle Brown's leave date now 17 Nov | **WF-02** TAP for Valeria to `you+oluwaseun.ogunleye@…` |
| **18 Nov** | Danielle Brown `active: false` | **WF-04** runs for Danielle: the intern's access ends live |
| 19 Nov | No changes | Step 11 evidence capture |
| **20 Nov** | Ebere Bello deleted by **WF-05** (13 Nov + 7); feed skips her (*no account*) | Then run the **expiry runbook** in [ADR-0007](../docs/adr/0007-p2-base-expiry-deadline.md) |

---

## Step 11: Capture evidence and commit (19 November)

**Why:** The licence window closes on the 20th. Everything that proves Phase 04 worked must be captured while the workflows and logs are still accessible.

```powershell
./07-Get-JmlEvidence.ps1 -Since 2026-11-07
./04-Get-ProvisioningResults.ps1 -Since 2026-11-07 -AsOf 2026-11-19
```

Copy the validation reports you want to keep from `output\` into `evidence\` (for example `validation-20261107.md` and `validation-20261114.md`).

Check `evidence\` contains:
- `…-lifecycle-workflows.json` (Step 6)
- `…-provisioning-reconciliation.json` (Steps 7 and 11)
- `…-jml-workflow-results.csv`, which should show WF-02 for Niamh, Nicole (on-demand) and Valeria, WF-03 for Miguel, and WF-04 for Ebere and Danielle
- Screenshots: mapping list, provisioning settings, TAP policy, the automation app's API permissions, Daniel's provisioning log *Steps*, WF-02's workflow history, Niamh's passkey registration

Open each file and check for TAP values or personal email addresses before committing. TAPs are never written by the scripts, but screenshots can catch them.

Commit on a branch and open a PR to the **Phase 04 JML lifecycle** milestone with label `risk:high` (it creates and disables accounts at scale).

## Later: scheduling the feed

The feed is manual for now, as agreed. Once the licence-dependent phases are done, it will run on a schedule. The natural fit is **GitHub Actions using workload identity federation**, built in Phase 10, so the scheduled job authenticates without any stored secret. Until then, the manual run is the control: if you don't run it, nothing changes, and WF-04 still disables leavers on time.

## Validation checklist

- [ ] Dry run: 199 to send, Sofía skipped, managers first
- [ ] Portal: provisioning app configured (custom attributes, mappings, create-only UPN, matching on employeeId)
- [ ] Accidental deletion threshold 20; provisioning on
- [ ] Portal: TAP enabled (one-time); automation app granted `SynchronizationData-User.Upload` with admin consent; workflow schedule 1 hour
- [ ] WF-02 built in the portal and reported *matches definition*; WF-01, 03, 04, 05 deployed; all **before 9 Nov**
- [ ] First load reconciled: exit code 0, Daniel adopted not duplicated
- [ ] Blocked-feed rehearsal shows DQ-15
- [ ] Niamh Jones registered a passkey with her TAP
- [ ] WF-03 ran for Miguel; WF-04 ran for Ebere and Danielle
- [ ] Evidence exported by 19 Nov; PR merged

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `403 Forbidden` from `/bulkUpload` | Upload permission missing, admin consent not granted, or not yet in the app's token | Check Step 5b (green status); open a new PowerShell session and reconnect |
| `400 Invalid Data Format` | Content type not `application/scim+json`, or malformed payload | Use the script (it sets the header); inspect the dry-run JSON |
| `202` but no provisioning log entries | Processing delay (5–10 min) or provisioning paused | Wait; confirm **Provisioning Status: On** |
| A danotech attribute stays empty | Attribute not added in 3a, or the name differs by a character | Compare the attribute list with the names in Step 3a exactly |
| `employeeHireDate` or `employeeLeaveDateTime` errors in the log | Target expects a date-time | Our values are ISO 8601 (`2026-11-09T08:00:00Z`). If still rejected, change the mapping type to **Expression** with `FormatDateTime([…HireDate], , "yyyy-MM-ddTHH:mm:ssZ", "yyyy-MM-ddTHH:mm:ssZ")` |
| Some reports have no manager after the first load | Manager created in the same cycle | Run the upload again; references resolve on the second pass |
| WF-02 didn't run for a joiner | Hire date before workflow creation; account outside scope; schedule not reached | **Run on demand** in the portal; check `companyName`; wait for the hourly run |
| No TAP email | Manager `mail` not set, or filtered as spam | Rerun Step 8; check the spam folder; issue the TAP in the portal |
| `python` not recognised | Python not on PATH | Reinstall with *Add python.exe to PATH*, or use `py` instead of `python` |

**Next:** [Phase 05: Groups, app roles and OIDC test app](../phase-05-groups-app-roles/)
