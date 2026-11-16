# Phase 06 Walkthrough: Privileged Access

**Goal:** Give 14 administrators dedicated admin accounts, make every admin role just-in-time through PIM (with approval for Tier 0), scope the Service Desk to workforce accounts, set up just-in-time application admin groups, and prove it all with a repeatable control test.

**When:** 16–20 November 2026 ([licensing record](../docs/licensing.md)).
**Time:** About 5 hours.
**Performed by:** Adaeze Nwosu (IAM Manager) and Kofi Owusu, with Oliver Hughes (CISO) as approver and Grace Robinson and Ngozi Balogun for the activation tests.

> ⚠️ **Order matters.** `adm.daniel.opara` keeps its permanent Global Administrator until Step 9. Removing it earlier would leave nobody able to run the scripts except break-glass. Step 9 has its own checklist: don't skip it.

## Prerequisites

- Phases 01, 04 and 05 complete: break-glass accounts work; 199 workforce accounts; dynamic job-role groups exist.
- **Managers' `mail` set** (Phase 04 Step 8): Oliver Hughes gets activation notices and approval emails at his plus-address.
- PowerShell 7.2+ with the Graph module. Microsoft Authenticator on your phone.

Scripts run from `phase-06-privileged-access\scripts\powershell\`. Portal paths may shift slightly between releases; use the admin center search box if one doesn't match.

| Step | Where | What |
|---|---|---|
| 1 | Portal | Re-test break-glass; look at the starting point |
| 2 | Portal | Build `adm.adaeze.nwosu` by hand |
| 3 | Portal | Build the AU-Workforce administrative unit |
| 4 | Script + portal | Create the other 12 admin accounts; passkeys |
| 5 | Portal | Configure Global Administrator's PIM settings |
| 6 | Script | Settings for the other 7 roles; check yours |
| 7 | Portal | First eligible assignment; first PIM-managed group |
| 8 | Script | The other 23 eligibilities and 4 groups |
| 9 | Portal | Remove Daniel's standing Global Administrator |
| 10–12 | Portal | Activation with approval; scoped helpdesk; app admin group |
| 13 | Script | Sync standing reader roles |
| 14 | Script | Control test and exercises |
| 15 | Portal + script | PIM alerts, audit history, evidence |

---

## Step 1: Re-test break-glass and look at the starting point

**Why:** This phase removes the last account with everyday standing Global Administrator. Before that, prove the way back in still works, exactly as Phase 01 required before Conditional Access.

1. Private window → sign in to the [Entra admin center](https://entra.microsoft.com) as **Emergency Access 01** with its passkey. Confirm **Roles & admins** opens. Sign out. (The Phase 01 alert should email you: that's working as designed.)
2. As `adm.daniel.opara`: **Entra ID → Roles & admins → Global Administrator → Assignments**. You'll see three **Active** assignments: two break-glass accounts and `adm.daniel.opara`, all **Permanent**.
3. **ID Governance → Privileged Identity Management → Microsoft Entra roles → Assignments**: same picture from PIM's view. The **Eligible** tab is empty. By the end of this phase, the Active tab shows only break-glass.

---

## Step 2: Build `adm.adaeze.nwosu` by hand

**Why:** Building one admin account by hand shows exactly what makes an account an *admin account*. The script then builds the other 12 and checks yours against the same rules.

**Users → All users → New user → Create new user**:

| Field | Value | Why |
|---|---|---|
| User principal name | `adm.adaeze.nwosu` | Naming convention: admin accounts start with `adm.` |
| Display name | `ADM - Adaeze Nwosu` | Visible everywhere, so nobody mistakes it for a daily account |
| Password | Auto-generate, **don't copy it** | Nobody should know an admin account's password; she'll use a passkey |
| Properties → Job title | `Privileged administrator account (T0)` | |
| Properties → Employee ID | `DT01014` | Links it to her HR record: when she leaves, the control test finds and disables it |
| Properties → Employee type | `AdminAccount` | Keeps it out of every workforce group and app, and puts it in the admin CA group |
| Properties → Usage location | `NG` | |
| Properties → Company name | **leave empty** | An empty company name keeps it out of HR lifecycle workflows and AU-Workforce |

**Review + create → Create**.

---

## Step 3: Build the AU-Workforce administrative unit

**Why:** An administrative unit limits *where* a role applies. Scoping Helpdesk Administrator to this unit means the Service Desk can help staff but can never touch an admin or break-glass account, whatever role it activates. It's dynamic, so joiners appear in it and leavers drop out automatically.

1. **Entra ID → Roles & admins → Admin units → Add**.
2. **Name:** `AU-Workforce`. **Description:** *DanotechInc workforce accounts only. Scope for Helpdesk Administrator (Tier 2).*
3. **Membership type: Dynamic User** → **Add dynamic query → Edit** →

   ```text
   (user.companyName -eq "DanotechInc") -and (user.employeeType -ne "AdminAccount")
   ```

4. Leave *Restricted management* off. **Create**.
5. After a few minutes, open it → **Users**: about 199 members, and no `adm.` or `bg-` accounts.

---

## Step 4: Create the other admin accounts and register passkeys

**Why:** Twelve near-identical accounts by hand would be slow and error-prone. The script builds them and checks the two that already exist (yours from Step 2, and Daniel's from Phase 01).

```powershell
./01-New-AdminAccounts.ps1 -WhatIf
./01-New-AdminAccounts.ps1
```

**Expected:** `adm.daniel.opara` and `adm.adaeze.nwosu` reported **Exists, matches design**; 12 **Created**; `GRP-DYN-ALL-AdminAccounts` created; `adm.adaeze.nwosu` and `adm.kofi.owusu` added to `GRP-LIC-EntraSuite`. If yours shows **DIFFERS**, the line says which property to fix.

**Register passkeys.** Each admin signs in once with a one-time Temporary Access Pass and registers a passkey. They never use a password. Do this now for the accounts the rest of the phase uses:

```powershell
$admins = 'adaeze.nwosu', 'kofi.owusu', 'grace.robinson', 'ngozi.balogun' | ForEach-Object { "adm.$_@danotechinc.onmicrosoft.com" }
$approvers = 'oliver.hughes', 'adaeze.nwosu' | ForEach-Object { "$_@danotechinc.onmicrosoft.com" }
..\..\..\phase-04-jml-lifecycle\scripts\powershell\06-New-TemporaryAccessPass.ps1 -UserPrincipalName ($admins + $approvers)
```

For each TAP: private window → <https://aka.ms/mysecurityinfo> → sign in with the TAP → **Add sign-in method → Passkey in Microsoft Authenticator**. (`adm.daniel.opara` already has Authenticator from Phase 01; add a passkey to it too.) The other 8 admin accounts can register later; eligibility doesn't need them to sign in.

---

## Step 5: Configure Global Administrator's PIM settings by hand

**Why:** PIM role settings decide what activation means: how long, what it requires, and who must approve. Configuring the most powerful role by hand shows every option. The script then applies the design to the other roles and checks your work against the same profile.

**ID Governance → Privileged Identity Management → Microsoft Entra roles → Settings → Global Administrator → Edit**:

**Activation tab**

| Setting | Value | Why |
|---|---|---|
| Activation maximum duration | **2** hours | Long enough for a change, short enough that a forgotten session expires |
| On activation, require | **Azure MFA** | Phase 07 upgrades this to a phishing-resistant authentication context |
| Require justification on activation | ✔ | Every activation explains itself in the audit log |
| Require ticket information on activation | ✔ | Ties Tier 0 activity to a change record |
| Require approval to activate | ✔ → **Select approvers:** Oliver Hughes, Adaeze Nwosu (daily accounts) | A second person for the most powerful role |

**Assignment tab**

| Setting | Value | Why |
|---|---|---|
| Allow permanent eligible assignment | ✘ → expire after **6 months** | Eligibility is re-justified twice a year (and reviewed in Phase 13) |
| Allow permanent active assignment | ✘ → expire after **1 month** | Even emergency "just give them active" assignments end |
| Require MFA / justification on active assignment | ✔ ✔ | |

**Notification tab:** under *Send notifications when eligible members activate this role*, **Role activation alert → Additional recipients:** Oliver Hughes's `mail` value (his plus-address).

**Update.**

> **Why approvers use daily accounts:** approving grants the approver nothing; it only lets someone else activate. PIM never lets you approve your own request.

---

## Step 6: Apply settings to the other seven roles, and check yours

```powershell
./02-Set-PimRoleSettings.ps1
```

**Expected:** `Global Administrator (built in the portal): matches T0-Approval`, then seven lines *applied and verified*: Privileged Role Administrator (T0, approvers Oliver Hughes and Daniel Opara), five T1 roles (4 hours, self-activate), Helpdesk Administrator (8 hours).

If yours **DIFFERS**, the script lists what's off (for example `activation doesn't require Ticketing`). Fix it in the portal and rerun.

Open **Settings → User Administrator** in the portal to see what the script set: you'll recognise every value.

---

## Step 7: First eligible assignment and first PIM-managed group (portal)

**Why:** *Eligible* is the heart of PIM: the right to activate, not the access itself. You create the most important one by hand. Then you build one PIM-managed group, the pattern Phase 08 uses for application admins.

### 7a. Make Daniel eligible for Global Administrator

1. **PIM → Microsoft Entra roles → Roles → Global Administrator → Add assignments**.
2. **Membership:** `ADM - Daniel Opara`. **Next**.
3. **Assignment type: Eligible**. Duration: **6 months** (the maximum you set in Step 5). **Assign**.

Daniel's admin account is now both *active* (permanent, from Phase 01) and *eligible*. The permanent one goes in Step 9.

### 7b. Build GRP-ROLE-PIM-WP-ADMIN

1. **Groups → New group:** Security, name `GRP-ROLE-PIM-WP-ADMIN`, description *WordPress administrator, just-in-time via PIM for Groups. Owner: Ngozi Balogun. Members are eligible only.*, **Microsoft Entra roles can be assigned to the group: Yes**, membership **Assigned**, **no members**. **Create**.

   *Role-assignable* means only Privileged Role Administrators and Global Administrators can change it. A Groups Administrator can't quietly add themselves to an admin group.
2. **PIM → Groups → Discover groups** → select `GRP-ROLE-PIM-WP-ADMIN` → **Manage groups**.
3. Open it → **Assignments → Add assignments** → role **Member**, select `ADM - Ngozi Balogun` → **Next** → **Eligible**, 6 months → **Assign**.

---

## Step 8: Create the remaining eligibility and groups

**Why:** 23 eligible assignments and 4 more groups are bulk work. The script derives them from the role model, checks your hand-built items exist, and refuses to make anything but an admin account eligible.

Run as `adm.daniel.opara` (still active Global Administrator):

```powershell
./03-New-PimEligibility.ps1
```

**Expected:**
- **Directory roles:** `exists adm.daniel.opara : Global Administrator`, then 23 `added`, including the four Helpdesk Administrator lines marked `[AU-Workforce]`.
- **PIM-managed groups:** `exists adm.ngozi.balogun eligible for GRP-ROLE-PIM-WP-ADMIN` (yours), 4 groups `created`, 6 more eligible members `added`, and `settings … App-Admin-Group verified` for all five groups.
- **Deferred to Phase 09:** Babatunde Bakare's subscription owner role and Priya Sharma's log workspace role.

In the portal: **PIM → Microsoft Entra roles → Assignments → Eligible**: 24 rows. Open a Helpdesk row and note the **Scope** column: `AU-Workforce`, not `Directory`.

---

## Step 9: Remove Daniel's standing Global Administrator

**Why:** This is the moment the tenant reaches zero standing privilege outside break-glass. It's also the riskiest step of the phase, so it has a checklist.

**Before you start, all of these must be true:**
- [ ] Both break-glass accounts signed in successfully today (Step 1)
- [ ] `adm.daniel.opara` is **eligible** for Global Administrator (Step 7a)
- [ ] Oliver Hughes and Adaeze Nwosu (approvers) can sign in with a passkey (Step 4)
- [ ] `adm.adaeze.nwosu` is eligible for Privileged Role Administrator (Step 8)

Then:
1. **PIM → Microsoft Entra roles → Assignments → Active assignments**.
2. On the `ADM - Daniel Opara` / Global Administrator row → **Remove** → **Yes**.
3. Sign out of every admin session.

**Check:** the **Active** tab for Global Administrator now shows only `Emergency Access 01` and `02`.

> **If anything goes wrong** (approvals not arriving, activation failing), sign in with a break-glass account and give `adm.daniel.opara` a time-bound *active* assignment from PIM. Then fix the cause.

---

## Step 10: Activate Global Administrator with approval

**Why:** This is the everyday experience of just-in-time admin, and the evidence that Tier 0 needs two people.

1. Private window → sign in as **`adm.daniel.opara`** → **PIM → My roles → Microsoft Entra roles → Eligible assignments → Global Administrator → Activate**.
2. Duration **1** hour; reason *"Phase 06 test: verify approval flow"*; ticket system `DanotechInc`, number `CHG-0601` → **Activate**. Status: **Pending approval**.
3. Another private window → sign in as **Oliver Hughes** (daily account) → **PIM → Approve requests** (or open the email at his plus-address) → select the request → **Approve** with *"Verified with Daniel, change CHG-0601"*.
4. Back as Daniel: refresh **My roles → Active assignments**. Global Administrator, ending in 1 hour.
5. Try approving it as Daniel himself: PIM doesn't offer you your own requests.

When finished, **Deactivate** it early: just-in-time means *only as long as needed*.

---

## Step 11: Prove the Service Desk can't touch admin accounts

**Why:** Scoping is invisible until someone tries to cross it. This step proves the Tier 2 boundary.

1. Sign in as **`adm.grace.robinson`** → **PIM → My roles** → activate **Helpdesk Administrator** (scope: AU-Workforce), 1 hour, reason *"Reset MFA for a user"*. No approval needed: it activates immediately.
2. **Entra ID → Roles & admins → Admin units → AU-Workforce → Users → Niamh Jones → Authentication methods**. Grace can manage them (don't change anything).
3. Now **Users → All users → ADM - Kofi Owusu → Reset password**. **Expected:** the action is unavailable or fails with insufficient privileges. Try **Emergency Access 01**: same.

Screenshot both outcomes for `evidence\`.

---

## Step 12: Just-in-time application admin with a group

**Why:** This is how application admin will work from Phase 08 onwards: activate a group membership, and the application role follows.

1. Sign in as **`adm.ngozi.balogun`** → **PIM → My roles → Groups → Eligible assignments → GRP-ROLE-PIM-WP-ADMIN (Member) → Activate**, 2 hours, *"Publish the year-end campaign page"*.
2. As `adm.daniel.opara` (or any reader): **Groups → GRP-ROLE-PIM-WP-ADMIN → Members**. Ngozi's admin account is listed. Two hours later, it won't be.

In Phase 08 this group is assigned the WordPress administrator role, so her next WordPress sign-in makes her an administrator, and after expiry, an editor again.

---

## Step 13: Sync the standing reader roles

**Why:** The role model gives the IAM team and GRC standing **Global Reader** and the SOC standing **Security Reader**. These can't be assigned to dynamic groups, so a script keeps them in step: movers and leavers lose them automatically.

```powershell
./04-Sync-StandingReaderRoles.ps1 -WhatIf
./04-Sync-StandingReaderRoles.ps1
```

**Expected:** Global Reader added to the 4 IAM team members and 4 GRC staff (CISO, GRC Manager, 2 GRC Analysts); Security Reader to the 5 SOC employees. **Not** Musa Afolabi: as a contractor he's in `GRP-DYN-JOB-SEC-SOC-LIMITED`, not `…-SEC-SOC`.

---

## Step 14: Run the control test, then break it on purpose

**Why:** The control test is what an auditor (and Phase 13) relies on. Seeing it pass proves the state; seeing it fail proves it actually detects problems.

```powershell
./05-Test-PrivilegedAccess.ps1
"Exit code: $LASTEXITCODE"
```

**Expected:** `PASS`, exit code `0`.

### Exercise A: standing admin on a daily account

1. Portal: **Roles & admins → User Administrator → Add assignments** → `Kofi Owusu` (his **daily** account), **Active, permanent** (use *Assign* outside PIM if PIM won't allow permanent).
2. Rerun the test. **Expected:** **PA-01** (permanent active) and **PA-02** (daily account), exit code `1`.
3. Remove the assignment; rerun. Pass again.

### Exercise B: a leaver keeps an admin account

1. Disable Jamal Davis's **daily** account (**Users → Jamal Davis → Edit properties → Account enabled: off**), as if HR had terminated him.
2. Rerun the test. **Expected:** **PA-05**: `adm.jamal.davis… is enabled but its owner's daily account is disabled`.
3. `./05-Test-PrivilegedAccess.ps1 -Remediate` disables `adm.jamal.davis` and revokes its sessions.
4. **Undo both:** re-enable Jamal's daily account and his admin account. Rerun: pass.

Without PA-05, Phase 04 would disable a leaver's daily account while their admin account stayed live: exactly finding F-02, for the most dangerous accounts in the tenant.

---

## Step 15: PIM alerts, audit history and evidence

**Why:** PIM watches for risky patterns itself, and its audit history is the primary evidence for every activation.

1. **PIM → Microsoft Entra roles → Alerts**. Review what's listed (for example *Roles are being assigned outside of PIM*, which Exercise A will have triggered). Open one to read the recommended fix.
2. **PIM → Microsoft Entra roles → Resource audit**: filter the last 7 days. You'll see Step 10's request, approval and activation, with Oliver's justification.
3. Export the rest:

```powershell
./06-Get-PimEvidence.ps1
./05-Test-PrivilegedAccess.ps1
```

`evidence\` should contain:
- `…-eligible-assignments.csv` (24 directory eligibilities)
- `…-pim-role-settings.csv` (8 roles and their settings)
- `…-role-activations.csv` (Daniel's approved activation, Grace's activation)
- `…-privileged-access-test.csv` (empty means pass)
- Screenshots: Global Administrator active tab showing only break-glass (Step 9), approval (Step 10), Grace's blocked reset (Step 11), Ngozi's group membership (Step 12), PIM alerts (Step 15)

Commit on a branch and open a PR to **Phase 06 Privileged access**, labelled `risk:high`.

## Validation checklist

- [ ] Break-glass re-tested before any change
- [ ] 14 admin accounts; script reports yours and Daniel's *matches design*
- [ ] AU-Workforce: ~199 members, no admin or break-glass accounts
- [ ] Global Administrator settings built in the portal and reported *matches T0-Approval*; 7 more roles applied
- [ ] 24 eligible directory assignments; Helpdesk scoped to AU-Workforce; 5 PIM-managed groups
- [ ] Only break-glass holds active Global Administrator
- [ ] GA activation needed and received Oliver Hughes's approval
- [ ] Helpdesk couldn't reset an admin or break-glass account
- [ ] Ngozi's group activation added her to `GRP-ROLE-PIM-WP-ADMIN` temporarily
- [ ] Reader roles synced; Musa Afolabi excluded
- [ ] Control test passes; both exercises detected and undone
- [ ] Evidence exported; PR merged

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Script 02 or 03: `403` | Your session lacks the role or scope | Activate Privileged Role Administrator (or use `adm.daniel.opara` before Step 9); `Disconnect-MgGraph` and rerun |
| `No PIM policy found … Group` | The group isn't managed by PIM yet | Script 03 makes the first eligibility before reading settings; for a hand-built group, do Step 7b's *Discover groups* |
| Eligible assignment request rejected: duration | Requested longer than the role allows | Settings must allow 6-month eligibility (Step 5/6) |
| Activation stuck *Pending approval* | Approver email went nowhere | Approver opens **PIM → Approve requests** directly; check Oliver's `mail` |
| `adm.` account can't sign in | No passkey registered | Issue a TAP (Step 4) |
| AU-Workforce has 0 members | Rule typo or processing delay | **Admin units → AU-Workforce → Dynamic membership rules → Validate** |
| Grace *can* reset an admin | She activated an unscoped role, or the admin account has a company name | Check the eligibility scope (Step 8); the admin account's company name must be empty |
| PA-05 fires for every admin | Daily accounts missing `employeeId` | Phase 04 reconciliation; employeeId must be set on daily accounts |

**Next:** [Phase 07: Zero Trust Conditional Access](../phase-07-zero-trust-conditional-access/)
