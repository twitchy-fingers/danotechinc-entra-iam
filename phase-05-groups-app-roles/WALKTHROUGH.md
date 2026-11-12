# Phase 05 Walkthrough: Groups, App Roles and the Danotech Expenses App

**Goal:** Build the role groups and prove their membership, license the cohort by group, register Danotech Expenses and connect its roles to groups, run it locally, host it on Azure App Service deployed from GitHub, and walk the full approval and separation-of-duties story with real accounts.

**When:** 10–11 November 2026 (after the Phase 04 feed for the 10th has run).
**Time:** About 5–6 hours.
**Performed by:** Emily Carter (IAM Engineer, technical owner of the app), Diego Ramírez (IAM Engineer), with Rachel Okafor (business owner) for the demo.

## Prerequisites

- **Phase 04 running:** the feed for 10 November has been uploaded, so `phase-04-jml-lifecycle\output\hr-snapshot-20261110.csv` exists and Miguel Hernández's transfer is in Entra ID.
- **PowerShell 7.2+** and **Python 3.10+**.
- Your Azure subscription (Phase 01 Step 9) and your GitHub repository.
- Microsoft Authenticator on a phone (it can hold several accounts).

Scripts run from `phase-05-groups-app-roles\scripts\powershell\`.

**Portal or script?** You build the first of each kind by hand: the first group, the licensing group, the app registration and its first role assignment, and everything in Azure. Scripts do the bulk work (40 more groups, 8 more role assignments) and **check your portal work against the model** before building on it ([ADR-0010](../docs/adr/0010-portal-and-script-balance.md)). Portal menu names can shift slightly between releases; if a path doesn't match exactly, use the portal's search box.

| Step | Where | What |
|---|---|---|
| 1 | Entra portal | Build the birthright group by hand |
| 2 | Script | Build the other 40; check yours |
| 3 | Script + portal | Prove membership; drift exercise |
| 4 | Entra portal | Licensing group with bulk import |
| 5 | Entra portal | Register the app: roles, permission, secret |
| 6 | Portal + script | Enterprise app settings; first assignment; check and assign the rest |
| 7 | Script | Run locally |
| 8 | Script | Prepare persona sign-ins |
| 9 | Azure portal | Create the App Service |
| 10 | Azure portal + GitHub | Deploy from GitHub with Deployment Center |
| 11–13 | Browser + Entra portal | Demo story, refusals, the mover |
| 14 | Script | Evidence and commit |

---

## Step 1: Build the birthright group by hand

**Why:** Groups are the bridge between HR data and application access. Building one by hand shows exactly what a dynamic group is: a membership rule over user attributes, evaluated continuously. The birthright group is the natural first one: everyone in the workforce, nobody else.

1. Open [`phase-03-rbac-design/generated/dynamic-group-rules.json`](../phase-03-rbac-design/generated/dynamic-group-rules.json) and copy the `membershipRule` of `GRP-DYN-ALL-Workforce`:

   ```text
   (user.accountEnabled -eq true) -and (user.companyName -eq "DanotechInc") -and (user.employeeType -in ["Employee","Contractor","Intern"])
   ```

2. [Entra admin center](https://entra.microsoft.com) as `adm.daniel.opara` → **Groups → All groups → New group**:
   - **Group type:** Security
   - **Group name:** `GRP-DYN-ALL-Workforce`
   - **Description:** *Role BR-WORKFORCE (Birthright). Managed as code from the Phase 03 role model.*
   - **Membership type:** **Dynamic User**
   - **Owners:** Adaeze Nwosu (the role owner in the model)
3. **Add dynamic query → Edit** (the text editor, top right of the rule builder) → paste the rule → **OK → Save → Create**.
4. Open the group → **Dynamic membership rules → Validate Rules** → add **Niamh Jones** and **ADM - Daniel Opara**. Niamh matches every condition; the admin account fails `employeeType` (it's `AdminAccount`). That's how admin accounts are kept out of every business role.

---

## Step 2: Build the other 40 groups, and check yours

**Why:** You've seen how one group is built. Doing 40 more by hand would be slow and error-prone, and any typo would silently give the wrong people the wrong access. The script creates them from the model, and checks the one you built against it.

```powershell
./01-New-RoleGroups.ps1 -WhatIf
./01-New-RoleGroups.ps1
```

**Expected:** `GRP-DYN-ALL-Workforce` reported as **Exists, matches model**, and 40 groups **Created**. If yours shows **Rule corrected (drift)**, the rule you pasted differed from the model and has been fixed; compare the two to see what changed.

Dynamic membership is evaluated in the background, typically 15–60 minutes for 41 new groups.

---

## Step 3: Prove membership matches the model

**Why:** "The groups exist" isn't evidence. This re-runs the Phase 03 simulation against **today's** HR snapshot (including Nicole Reed's start and Miguel's transfer) and compares every group with the model, person by person. Zero differences ties Phases 02 to 05 together: valid data, correct model, correct provisioning, correct rules.

```powershell
./02-Test-GroupMembership.ps1 -AsOf 2026-11-10
"Exit code: $LASTEXITCODE"
```

**Expected:** every group shows no missing and no unexpected members; exit code `0`. Some sizes to recognise:

| Group | Members | Why this number |
|---|---|---|
| `GRP-DYN-ALL-Workforce` | 195 | 199 accounts minus 4 pre-hires still disabled |
| `GRP-DYN-DEPT-Finance` | 19 | 18 + Miguel Hernández, transferred on the 10th |
| `GRP-DYN-JOB-FIN-FPA` | 5 | 3 analysts + the CFO + Miguel |
| `GRP-DYN-JOB-SAL-LEADER` | 6 | Was 7: Miguel left it when his job code changed |
| `GRP-DYN-JOB-PeopleManagers` | 29 | Everyone with direct reports (derived in Phase 04) |

If groups show differences straight after Step 2, processing hasn't finished. Wait 30 minutes and rerun.

### Exercise: configuration drift

**Why:** Someone will eventually "fix" a rule in the portal. Because the model is the source of truth, the script detects and repairs the drift.

1. In the portal, edit `GRP-DYN-JOB-FIN-AP`'s rule: change `"FIN-AP"` to `"FIN-PAY"`. Save.
2. After a few minutes, `./02-Test-GroupMembership.ps1 -AsOf 2026-11-10` shows **4 missing, 2 unexpected** in that group.
3. `./01-New-RoleGroups.ps1` reports **Rule corrected (drift)**.
4. After processing, the membership test is clean again.

---

## Step 4: Build the licensing group (portal, with bulk import)

**Why:** With group-based licensing, a seat follows group membership: add someone and they're licensed, remove them and the seat is freed. The group's membership *is* the record of who holds the 25 seats. It's an **assigned** group, not dynamic, because the cohort is a deliberate selection ([ADR-0006](../docs/adr/0006-trial-window-build-order-and-licensed-cohort.md)), not an attribute rule. Adding 23 people one by one would be tedious, so this uses the portal's own bulk import.

1. **Groups → New group:** Security, name `GRP-LIC-EntraSuite`, membership type **Assigned**, description *Licensed cohort (25 seats), per ADR-0006. Owner: IAM Manager.* → **Create**.
2. Open the group → **Members → Bulk operations → Import members**. Download the template and compare its header lines with [`config/licensing-cohort-import.csv`](config/licensing-cohort-import.csv). If they're identical, upload our file. If Microsoft's template differs, paste our 23 user rows into the downloaded template and upload that.
3. **Submit**, then check **Bulk operation results**: 23 succeeded. `adm.adaeze.nwosu` and `adm.kofi.owusu` aren't in the file because they don't exist yet; Phase 06 adds them.
4. **Licenses → Assignments** → tick the Entra Suite product (and the P2 product if it has enough seats) → **Save**.
5. After a few minutes, the group's **Licenses** page should show no errors. If some members fail, the usual cause is a product with fewer seats than members: assign only the product with 25 seats.

---

## Step 5: Register Danotech Expenses (portal)

**Why:** The app registration is the app's identity in Entra ID: who it is, where it may send tokens, which roles it defines, and how it proves itself. Building it by hand is the best way to understand each part.

### 5a. Register the app

1. **Entra ID → App registrations → New registration**.
2. **Name:** `app-danotech-expenses`
3. **Supported account types:** *Accounts in this organizational directory only (single tenant)*. Only DanotechInc accounts can ever sign in.
4. **Redirect URI:** platform **Web**, `http://localhost:5000/auth/callback`. Entra ID will only ever send authorization codes to URIs listed here.
5. **Register**. On **Overview**, copy the **Application (client) ID**.
6. **Authentication:** confirm both implicit grant boxes (*Access tokens*, *ID tokens*) are **unticked**. The app uses the authorization code flow; implicit grant puts tokens in the browser URL and isn't needed.

### 5b. Create the five app roles

**App roles → Create app role**, five times, using [`config/expenses-app-roles.json`](config/expenses-app-roles.json). For each: **Allowed member types: Users/Groups**, and enable it.

| Display name | Value (must match exactly) | Description |
|---|---|---|
| Submit expense claims | `Expenses.Submit` | Submit and track your own expense claims. |
| Approve team expense claims | `Expenses.Approve` | Approve or reject claims from your direct reports. |
| Finance review | `Expenses.Review` | Check approved claims against policy and receipts. |
| Release payments | `Expenses.Pay` | Release reviewed claims for payment. |
| Audit expenses (read-only) | `Expenses.Audit` | Read all claims and the activity log. No changes. |

The **Value** is what appears in the token's `roles` claim and what the app checks, so a typo means the role never works. The script in Step 6 verifies all five.

### 5c. API permission and admin consent

1. **API permissions:** `Microsoft Graph → User.Read (Delegated)` is usually already listed. If not: **Add a permission → Microsoft Graph → Delegated → User.Read**.
2. **Grant admin consent for DanotechInc → Yes**.

**Why admin consent:** Phase 01 turned off user consent, so no user can grant an app access to their data. That's an admin decision, made once here and visible in the audit log.

### 5d. Client secret

1. **Certificates & secrets → Client secrets → New client secret**. Description: *phase05-temporary (removed in Phase 10)*. **Expires: Custom, 30 days**.
2. Copy the **Value** immediately. It's shown only once.
3. Create the settings file **outside the repository**, from the example:

```powershell
New-Item -ItemType Directory -Path "$HOME\danotech-secrets" -Force | Out-Null
Copy-Item ..\..\app\expenses.env.example "$HOME\danotech-secrets\expenses.env"
[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))   # your session key
notepad "$HOME\danotech-secrets\expenses.env"
```

Fill in `CLIENT_ID`, `CLIENT_SECRET` and `FLASK_SECRET_KEY` (the hex string you just generated), and save.

> **Why 30 days, and why it's temporary:** a client secret is a password for the app. Short lifetime limits the damage if it leaks. Phase 10 removes it entirely: the app will prove its identity with its App Service managed identity, so there's no secret to steal ([ADR-0009](../docs/adr/0009-expenses-app-hosting-and-authorization.md)).

---

## Step 6: Configure the enterprise app and assign roles

**Why:** The app registration defines the app; the **enterprise app** controls who may use it in DanotechInc. "Assignment required" means Entra ID refuses a token to anyone without an app role, so they never reach the app at all.

### 6a. In the portal

1. **Enterprise apps → app-danotech-expenses → Properties → Assignment required? Yes → Save**.
2. **Users and groups → Add user/group** → Users and groups: `GRP-DYN-ALL-Workforce` → Role: **Submit expense claims** → **Assign**.

That first assignment means everyone in the workforce can submit claims.

### 6b. Check and assign the rest

```powershell
./03-Set-ExpensesAppRoleAssignments.ps1
```

**Expected:** every check **PASS** (single tenant, localhost redirect URI, implicit grant off, five roles, User.Read requested and consented, assignment required, secret ≤ 31 days). Then:
- `exists GRP-DYN-ALL-Workforce -> Expenses.Submit` (yours)
- 8 × `added`, e.g. `GRP-DYN-JOB-FIN-AP -> Expenses.Pay`, `GRP-DYN-JOB-FIN-CONTROLLER -> Expenses.Review` and `-> Expenses.Pay`
- `skip GRP-AP-EXP-AUDITOR`: an access package group, built in Phase 12
- `9 role-to-group assignments expected; 9 present`

If any check **FAILs**, the script stops before assigning anything. Fix the item in the portal and rerun. If it reports **NOT IN MODEL**, an assignment was made in the portal that the role model doesn't call for; remove it, or change the model first.

**Look at the result in the portal:** **Users and groups** now lists nine group-to-role assignments. None of them was hand-picked except the first.

---

## Step 7: Run it locally

**Why:** Testing on `localhost` first separates problems with the app and its Entra ID configuration from problems with Azure hosting.

```powershell
./04-Start-ExpensesLocal.ps1
```

Open <http://localhost:5000> in a **private window** and sign in as **Niamh Jones** with the passkey she registered in Phase 04.

**Expected:**
- **Home:** *Expenses.Submit: Yes*, everything else *No*. She's a new Account Executive, so that's correct.
- **Token** page: `aud` is the app's client ID, `roles` is `["Expenses.Submit"]`, and `amr` shows how she authenticated (e.g. `fido`, `mfa`).
- **My claims:** *Goes to your manager: Brandon Collins*. That came from the Graph access token, used once and discarded.
- **Finance** or **Audit:** **403**, because her token has no such role.

Stop the app with **Ctrl+C**.

---

## Step 8: Prepare the persona sign-ins

**Why:** The separation-of-duties story needs real people with real roles. Six people is bulk work, so it's scripted. Each persona signs in with genuine MFA (Conditional Access CA001 applies), so the demo exercises the same controls production would.

```powershell
$personas = 'brandon.collins', 'rachel.okafor', 'kwabena.kyei', 'ama.amoah', 'nana.agyeman', 'miguel.hernandez' |
    ForEach-Object { "$_@danotechinc.onmicrosoft.com" }
..\..\..\phase-04-jml-lifecycle\scripts\powershell\06-New-TemporaryAccessPass.ps1 -UserPrincipalName $personas
```

For each TAP shown: in a new private window open <https://aka.ms/mysecurityinfo>, sign in with the TAP, add **Microsoft Authenticator**, sign out, then press Enter for the next. Authenticator holds all six accounts. A separate browser profile per persona keeps their sessions apart later.

---

## Step 9: Create the App Service (Azure portal)

**Why:** A public HTTPS address is a real production pattern: TLS, a cloud redirect URI, and settings held by the platform rather than in files. It also gives the portfolio a live link. Doing it in the Azure portal shows every choice a web app involves.

Sign in to the [Azure portal](https://portal.azure.com) as `adm.daniel.opara`.

### 9a. Resource group

**Resource groups → Create:** name `rg-danotech-apps-prd-eus`, region **East US**. **Tags:** `owner = IAM`, `phase = 05`, `costCenter = CC5000`, `environment = prd` → **Review + create → Create**.

### 9b. Web app

**App Services → Create → Web App**:

| Tab | Setting | Value | Why |
|---|---|---|---|
| Basics | Resource group | `rg-danotech-apps-prd-eus` | |
| | Name | `danotech-expenses-<your initials>` (must be globally unique) | Becomes part of the URL |
| | Publish | **Code** | We deploy Python source, not a container |
| | Runtime stack | **Python 3.12** | |
| | Operating system | **Linux** | |
| | Region | **East US** | Same region as the log workspace |
| | Pricing plan | **Create new** → `asp-danotech-apps-f1` → **Free F1** | No cost |
| Deployment | Continuous deployment | **Disable** | Set up properly in Step 10 |
| Monitoring | Application Insights | **No** | Keeps the lab simple and free |
| Tags | | Same four tags as the resource group | |

**Review + create → Create**. When it finishes, open the app and copy its **Default domain** from **Overview**.

### 9c. Configuration

1. **Settings → Environment variables → App settings**, add each of these, then **Apply**:

   | Name | Value |
   |---|---|
   | `TENANT_ID` | `danotechinc.onmicrosoft.com` |
   | `CLIENT_ID` | the Application (client) ID |
   | `CLIENT_SECRET` | the secret value (from your `expenses.env`) |
   | `FLASK_SECRET_KEY` | the session key (from your `expenses.env`) |
   | `REDIRECT_URI` | `https://<default domain>/auth/callback` |
   | `EXPENSES_DB` | `/home/data/expenses.db` |
   | `SCM_DO_BUILD_DURING_DEPLOYMENT` | `true` |

   App settings are encrypted at rest and injected as environment variables at runtime. The secret never appears in code, in GitHub or in the deployment package.
2. **Settings → Configuration → General settings:** **Startup Command** `gunicorn --bind=0.0.0.0 --timeout 600 app:app`; **HTTPS Only: On** (on some portal versions this toggle is under **Custom domains**) → **Save**.

### 9d. Add the cloud redirect URI (Entra portal)

**App registrations → app-danotech-expenses → Authentication → Web → Add URI** → `https://<default domain>/auth/callback` → **Save**. Entra ID now accepts both localhost and the cloud address.

---

## Step 10: Deploy from GitHub with Deployment Center

**Why:** Deploying from Git means the running app always matches a known commit, and every release is a recorded GitHub Actions run. Deployment Center sets up the whole pipeline from the portal, including a secretless sign-in from GitHub to Azure.

### 10a. Create a release branch

Your `main` branch rejects direct commits (Phase 00 ruleset), and Deployment Center commits its workflow file directly to the branch you choose. So deploy from a **release branch**, a common pattern that keeps `main` protected: changes reach production by merging `main` into the release branch.

On GitHub: **Code → branch selector → View all branches → New branch** → name `release/expenses`, source `main` → **Create**.

### 10b. Connect Deployment Center

App Service → **Deployment → Deployment Center → Settings**:

| Setting | Value |
|---|---|
| Source | **GitHub** → **Authorize** (sign in to GitHub) |
| Organization / Repository | your account / `danotechinc-entra-iam` |
| Branch | `release/expenses` |
| Workflow option | **Add a workflow** |
| Authentication type | **User-assigned identity** (create new) |

**Save**. Deployment Center now:
- commits a workflow file to `.github/workflows/` on `release/expenses`
- creates a managed identity with a **federated credential** that trusts GitHub Actions runs from your repository's release branch, and grants it deploy rights on the web app
- stores the identity's client, tenant and subscription IDs as GitHub repository secrets. These are identifiers, not passwords: the workflow proves itself with a short-lived GitHub OIDC token instead. Phase 10 takes this pattern apart in detail.

### 10c. Point the workflow at the app folder

The generated workflow assumes the app is at the root of the repository. Ours is in `phase-05-groups-app-roles/app`, so its first run fails. That's expected. Fix it in GitHub:

1. Switch to the `release/expenses` branch → open the new file in `.github/workflows/` → ✏️ edit.
2. Change the two `run:` lines in the **build** job:

   ```yaml
   # was: run: pip install -r requirements.txt
   run: pip install -r phase-05-groups-app-roles/app/requirements.txt

   # was: run: zip release.zip ./* -r
   run: cd phase-05-groups-app-roles/app && zip ../../release.zip ./* -r
   ```

3. **Commit changes** directly to `release/expenses`. The commit triggers a new run.
4. **Actions** tab: the *build* and *deploy* jobs turn green in a few minutes.

Open `https://<default domain>`. The first request can take 2–3 minutes while App Service installs packages; F1 apps also sleep when idle, so the first visit after a break is slow.

**Check:** **App Service → Deployment Center → Logs** lists the deployment with its commit ID. Any running version can be traced to an exact commit.

---

## Step 11: Run the demo story on the live app

**Why:** This is the evidence that separation of duties isn't just a row in a spreadsheet: the business process enforces it, and attempts to break it are recorded.

Use the published URL, with a different private window (or profile) for each person. The story is described in the [README](README.md#the-demo-story):

| Step | Sign in as | Do | Expected |
|---|---|---|---|
| 1 | Niamh Jones | **My claims** → 340 USD, Client entertainment, "Client dinner" | *Submitted to Brandon Collins* |
| 2 | Brandon Collins | **Approvals** → Approve | Approved |
| 3 | Rachel Okafor | **Finance → Finance review** → Review | Reviewed |
| 4 | Ama Amoah | **Finance → Payment release** → Pay | Paid |
| 5 | Ama Amoah | **My claims** → 95.50 USD, Travel, "Taxi to supplier" | *Submitted to Rachel Okafor* |
| 6 | Rachel Okafor | **Approvals** → Approve; then **Finance → Review** on the same claim | Approved; then **"You can't review a claim you submitted or approved"** |
| 7 | Kwabena Kyei | **Finance → Review** | Reviewed |
| 8 | Rachel Okafor | **Finance → Pay** | **"SOD-01: you approved this claim, so you can't release its payment (EXC-001 compensating control)"** |
| 9 | Ama Amoah | **Finance → Pay** her own claim | **"You can't pay your own claim"** |
| 10 | Nana Agyeman | **Audit** | All claims, and the activity log with three *Denied* entries and their reasons |

Screenshot steps 8 and 10 for `evidence\`. Step 8 is the proof that the EXC-001 compensating control works.

---

## Step 12: Prove who can't get in

**Why:** Access control is as much about who is refused as who is allowed.

Sign in to the app as `adm.daniel.opara`. Admin accounts have `employeeType = AdminAccount`, so they're in no workforce group and hold no app role. **Expected:** Entra ID refuses before the app is reached, with **AADSTS50105** (*not assigned to a role for the application*). That's the Phase 01 rule working: admin accounts don't use business apps.

Find the refusal in the portal: **Entra ID → Monitoring & health → Sign-in logs**, filter **Application** `app-danotech-expenses`, **Status** *Failure*. Open it: the **Basic info** tab shows the error code and reason.

---

## Step 13: Confirm the mover's access changed

**Why:** This closes the "copy Ama" loop from Phase 03. Miguel's access should have changed purely because HR changed his job code, with nobody editing a group or the app.

1. Sign in to the app as **Miguel Hernández**. **Home** shows *Expenses.Audit: Yes* (from `GRP-DYN-JOB-FIN-FPA`), and **Audit** opens.
2. **Entra ID → Monitoring & health → Audit logs**, category **GroupManagement**, target **Miguel Hernández**: he was **removed from** `GRP-DYN-JOB-SAL-LEADER` and `GRP-DYN-DEPT-Sales` and **added to** `GRP-DYN-JOB-FIN-FPA` and `GRP-DYN-DEPT-Finance`, all initiated by the dynamic membership service, not by a person.
3. **Users → Miguel Hernández → Groups** shows his current memberships at a glance.

Screenshot the audit entries and his Home page for `evidence\`.

---

## Step 14: Capture evidence and commit

```powershell
./05-Get-Phase05Evidence.ps1
```

`evidence\` should now contain:
- `…-groups.csv`: every group, type, member count and rule
- `…-group-membership-test.csv` (Step 3): zero differences
- `…-app-role-assignments.csv`: 9 group-to-role assignments
- `…-expenses-signins.csv`: successes, plus the AADSTS50105 refusal
- `…-expenses-app-config.json`: redirect URIs and the secret's expiry date (not its value)
- Screenshots: the rule validation (Step 1), bulk import results and licence status (Step 4), the five app roles and admin consent (Step 5), Deployment Center logs (Step 10), the SOD-01 denial and audit page (Step 11), the AADSTS50105 sign-in (Step 12), Miguel's group changes (Step 13)

Commit on a branch from `main` and open a PR to the **Phase 05 Groups and app roles** milestone. Before committing, confirm `app\.venv\` and `app\instance\` aren't staged (both are git-ignored) and nothing from `danotech-secrets` is in the repository. To release a future change to the app: merge `main` into `release/expenses`.

## Validation checklist

- [ ] Birthright group built in the portal; script reports *matches model*; 40 more created
- [ ] Membership test exit code 0 for 10 Nov; drift exercise detected and corrected
- [ ] `GRP-LIC-EntraSuite` built in the portal: 23 members by bulk import, no licence errors
- [ ] App registration built in the portal; `03-Set-ExpensesAppRoleAssignments.ps1` all PASS; 9 assignments
- [ ] App works locally
- [ ] App Service created in the Azure portal; app settings hold the secret; HTTPS only
- [ ] Deployment Center deploys from `release/expenses` via a user-assigned identity; Actions run green
- [ ] Demo story complete; SOD-01 denial and audit log captured
- [ ] Admin account refused with AADSTS50105
- [ ] Miguel's group changes and new role confirmed
- [ ] Evidence exported; PR merged

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Group has 0 members after an hour | Rule syntax issue or processing paused | **Dynamic membership rules → Validate Rules** against a known member |
| Bulk import: some rows failed | UPN typo, or account doesn't exist yet | Check **Bulk operation results**; adm accounts are added in Phase 06 |
| Step 6b: a FAIL | A portal setting differs from the design | The FAIL line names it; fix in the portal and rerun |
| **AADSTS50105** for a normal user | Not in any group with an app role, or processing unfinished | Check the user's groups; wait |
| **AADSTS50011** redirect URI mismatch | URI in the app registration differs from `REDIRECT_URI` (http vs https, trailing slash) | Compare **Authentication** with the app setting |
| **AADSTS65001** consent required | Admin consent missing | Step 5c |
| Roles missing in the token | Old session, or added to the group after signing in | Sign out of the app and back in |
| First Actions run failed | Expected: the generated workflow looks for files at the repository root | Step 10c |
| Actions *deploy* job fails at login | Identity or federated credential not created, or wrong branch | Re-save Deployment Center settings; confirm the branch is `release/expenses` |
| *Application Error* in the browser | Startup failure | App Service → **Log stream**; check the startup command and app settings |
| Sign-in fails after 30 days with an invalid client secret error | Temporary secret expired | New secret in the portal; update the app setting and `expenses.env` (or do Phase 10, which removes it) |

**Next:** [Phase 06: Privileged access](../phase-06-privileged-access/)
