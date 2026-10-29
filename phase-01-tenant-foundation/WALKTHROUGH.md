# Phase 01 Walkthrough: Tenant Foundation and Hardening

**Goal:** Make `danotechinc.onmicrosoft.com` safe to build on: guaranteed recovery, no privileged daily account, hardened defaults, baseline Conditional Access, an automation identity and a log pipeline.

**Time:** 3–4 hours, plus a 15–30 minute wait for logs to arrive.
**Performed by:** Adaeze Nwosu (IAM Manager) and Kofi Owusu (Senior IAM Engineer), with Daniel Opara present for the steps involving his accounts. In this lab, you play all three.

> ⚠️ **Order matters.** Steps 2–4 (break-glass) must be finished and tested **before** Step 7 (Conditional Access). The scripts enforce this with lockout guards, but understand why: every Conditional Access mistake is recoverable only if a break-glass account works.

## Which account to use

| Steps | Sign in as | Why |
|---|---|---|
| 1–5 | `daniel.opara@` | Still the only Global Admin at this point. |
| 6–8, 10–13 | `adm.daniel.opara@` | From Step 6 on, admin work moves to the admin account. |
| 9 (Azure sign-up) | `daniel.opara@` | Billing belongs to the business owner, not the admin account. |

Always run `Disconnect-MgGraph` before switching accounts, or Graph PowerShell will reuse the cached token.

## Prerequisites

- **PowerShell 7.2+** ([install](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)). The scripts use PowerShell 7 syntax and won't run in Windows PowerShell 5.1.
- **Python 3.10+** (Step 13 only).
- **Two FIDO2 security keys** (for example YubiKey), one per break-glass account. No keys? See the note in Step 3.
- **A phone with Microsoft Authenticator** for the CEO's admin account.
- A credit or debit card and phone number for Azure sign-up (Step 9). The free account doesn't charge it.
- A personal (external) email address to receive alerts. DanotechInc has no mailboxes ([ADR-0001](../docs/adr/0001-use-onmicrosoft-domain.md)).

---

## Step 1: Install tooling and capture the "before" baseline

**Why:** You can't prove improvement without a starting point. The baseline JSON is the first piece of audit evidence in the program. It shows that on day one there was one Global Admin, no Conditional Access and security defaults on. GRC (Nana Agyeman) will compare it with the "after" snapshot in Step 13.

```powershell
cd phase-01-tenant-foundation/scripts/powershell
./00-Install-Tooling.ps1
./01-Get-TenantBaseline.ps1 -Label before
```

Sign in as `daniel.opara@` and consent to the read-only scopes when prompted. This is a one-time consent for the Microsoft Graph Command Line Tools app.

**Check:** the output shows your licences, `Security defaults enabled: True` and a single Global Administrator. Copy the licence details into `docs/licensing.md` if you didn't in Phase 00.

---

## Step 2: Create the break-glass accounts

**Why:** Every control you build from here can lock you out: a Conditional Access typo, an MFA outage, a deleted authentication method, a federation failure in Phase 08. Break-glass accounts are deliberately excluded from all of it, so there's always a way back in. Microsoft's guidance is at least two, so one lost key or one locked account isn't fatal.

**Before running:** decide where the two credentials will be stored (see Step 3). The passwords are shown once.

```powershell
./02-New-BreakGlassAccounts.ps1
```

The script:
1. Enables the **Passkey (FIDO2)** authentication method so the accounts can register keys.
2. Creates `GRP-CA-Exclude-BreakGlass` as a **role-assignable** group. Only Privileged Role Administrators and Global Admins can change its membership, so a lower-tier admin can't add themselves to it and bypass every policy.
3. Creates `Emergency Access 01` and `02` with a random UPN token (for example `bg-k7q2-01@`) and a 64-character random password with no expiry.
4. Adds both to the exclusion group and assigns **permanent, active** Global Administrator.

Copy the printed **object IDs** and the **exclusion group ID** into a scratch note. You'll need them in Step 12.

> **Why permanent and not PIM?** PIM activation depends on MFA, on PIM itself and on approvers being available. Break-glass exists for when those things are broken. Phase 06 explicitly excludes these two accounts from PIM.

---

## Step 3: Secure the break-glass credentials

**Why:** A break-glass account is only as strong as how its credentials are stored. Each account has two factors (password and FIDO2 key), and the two accounts are stored separately, so no single person or location can use both, and losing one location doesn't lose both.

For **each** account:

1. Open a **private/incognito** browser window and go to <https://aka.ms/mysecurityinfo>.
2. Sign in with the break-glass UPN and password.
3. Security defaults are still on, so you'll be prompted to set up MFA. Choose **Add sign-in method → Passkey (or Security key)** and register that account's FIDO2 key.
4. Sign out and close the window.

Then store the credentials:

| Item | Break-glass 01 | Break-glass 02 |
|---|---|---|
| FIDO2 key | Safe A (e.g. Atlanta HQ office safe) | Safe B (e.g. CIO's home safe, or a bank deposit box) |
| Password | Sealed envelope in safe A, or a password manager vault restricted to the CIO and CISO | Same pattern, separate location |
| Access log | Paper log in each safe: who opened it, when, why | Same |

> **No hardware keys in the lab?** Register a **passkey in Microsoft Authenticator** on a phone you don't use for anything else, or a platform passkey (Windows Hello) on a dedicated device. Document this as a compensating control in `evidence/`. In production, hardware keys are the expected standard because they have no dependency on a phone or a single device.

---

## Step 4: Test both break-glass accounts

**Why:** An untested recovery path is a hope, not a control. Testing now, while nothing depends on it, is much better than discovering a typo in a stored password during an outage.

For each account:
1. Private browser window → <https://entra.microsoft.com>.
2. Sign in with the UPN, password and FIDO2 key.
3. Confirm you can open **Identity → Roles & admins** (proves the Global Admin role works).
4. Sign out.

Take a screenshot of a successful sign-in in **Identity → Monitoring & health → Sign-in logs** (filter on the break-glass user) and save it as `evidence/YYYYMMDD-breakglass-test.png`. This test is repeated **quarterly**. Phase 15 turns it into a runbook.

---

## Step 5: Create the CEO's admin account

**Why:** Daniel's daily account reads email and opens links, which makes it the account most likely to be phished. Putting Global Admin on a separate account means a compromised inbox doesn't hand an attacker the tenant. Both accounts share Daniel's employee ID (`DT01001`), which links them for access reviews and means the leaver process can find and disable both.

```powershell
./03-New-AdminAccount.ps1 -FirstName Daniel -LastName Opara -EmployeeId DT01001
```

Then:
1. Private window → <https://aka.ms/mysecurityinfo> → sign in as `adm.daniel.opara@` with the temporary password.
2. Set a new strong password. Store it in Daniel's password manager, **separate** from his daily account.
3. Register **Microsoft Authenticator** as the MFA method (and a passkey if you have one). Phase 07 makes phishing-resistant methods mandatory for admins.

**Rule from now on:** `adm.daniel.opara` is used only for admin portals and admin scripts. It never reads email and never browses the web.

---

## Step 6: Harden tenant defaults

**Why:** Out of the box, every member can register applications, consent to apps reading their data, create security groups and invite guests. Each of those creates identities or grants access outside any approval process. Turning them off before 200 users arrive means good behaviour is the default rather than a clean-up project later.

### 6a. Scripted settings

```powershell
Disconnect-MgGraph
./04-Set-TenantHardening.ps1     # sign in as adm.daniel.opara
```

| Setting | Why |
|---|---|
| Users can't register apps | App registrations are identities with credentials; they're created by the IAM team. |
| User consent disabled + admin consent workflow | A malicious "Sign in with Microsoft" app can read mail and files with one click. Now users *request* the app and an admin reviews the permissions. |
| Users can't create security groups or tenants | Groups grant access; shadow tenants sit outside DanotechInc's controls. |
| Guest invites: admins and Guest Inviter only | Guests come in through governed access packages in Phase 12. |
| Guests get the most restrictive role | A guest can't browse the staff directory and map out targets. |
| No email-verified self-service sign-up | Stops unmanaged ("viral") accounts appearing in the tenant. |

The script saves before and after copies of the authorization policy to `evidence/`.

### 6b. Portal-only settings

These have no Graph API, so set them in the [Entra admin center](https://entra.microsoft.com) and screenshot each:

| Where | Setting | Value | Why |
|---|---|---|---|
| Users → User settings | Restrict access to Microsoft Entra admin center | **Yes** | Non-admins don't need to browse the admin portal. (It doesn't block Graph or PowerShell, which is why the authorization settings above still matter.) |
| Users → User settings | LinkedIn account connections | **No** | Stops directory data being shared with a third-party service. |
| Groups → General | Users can create Microsoft 365 groups… | **No** | Same reasoning as security groups. |
| Groups → General | Owners can manage group membership requests in My Groups | **No** | Membership requests go through access packages (Phase 12). |

---

## Step 7: Replace security defaults with baseline Conditional Access

**Why:** Security defaults can't exclude break-glass accounts and can't be tuned, and they can't run alongside Conditional Access. This step swaps them **like for like**: the same protections (MFA everywhere, legacy auth blocked), now as Conditional Access policies with the break-glass exclusion. Protection never drops, and Phase 07 has a proper foundation to build on.

**Why deploy straight to "enabled", not report-only?** Report-only is for testing *new* behaviour. These policies reproduce what security defaults already enforce, so a report-only period would mean a window of weaker protection than today. Phase 07's new policies go through report-only first.

```powershell
./05-Deploy-BaselineConditionalAccess.ps1    # as adm.daniel.opara
```

The script refuses to run unless the exclusion group has two members, then disables security defaults and creates:

| Policy | Effect |
|---|---|
| `CA000-AllUsers-AllApps-BlockLegacyAuth` | Blocks IMAP, POP, SMTP auth, Exchange ActiveSync and other legacy protocols that can't do MFA. |
| `CA001-AllUsers-AllApps-RequireMFA` | MFA for everyone except break-glass. |
| `CA100-Admins-AllApps-RequireMFA` | MFA for 14 privileged roles. Overlaps with CA001 today on purpose: Phase 07 upgrades this one to phishing-resistant MFA without touching the workforce policy. |

The policy definitions live in [`policies/conditional-access/`](policies/conditional-access/) so every future change is a reviewed diff.

**Test immediately**, keeping your current admin session open in case you need to roll back:

1. New private window → sign in as `adm.daniel.opara@` → you should get an MFA prompt.
2. Use the **What If** tool (**Conditional Access → Policies → What If** in the Entra admin center) for:
   - `adm.daniel.opara`, All cloud apps → CA001 and CA100 apply.
   - A break-glass account → **no policies apply**. This is the most important check.

> **Rollback:** if anything goes wrong, sign in with a break-glass account and set the affected policy to **Off**, or re-enable security defaults (**Identity → Overview → Properties → Manage security defaults**).

---

## Step 8: Remove standing admin rights from Daniel's daily account

**Why:** Until now the daily account still holds Global Admin, so the phishing risk from the scenario is still open. Now that the admin account and both break-glass accounts are proven, the daily account can be demoted.

```powershell
./06-Remove-StandingAdminFromDailyAccount.ps1    # as adm.daniel.opara
```

The script refuses to run if you're signed in as the daily account, or if fewer than three *other* Global Admins exist. It also sets `employeeId = DT01001` on the daily account. When the HR feed goes live in Phase 04, inbound provisioning matches on `employeeId`, so it **adopts** Daniel's existing account instead of creating a duplicate `daniel.opara2`.

**Check:** sign in as `daniel.opara@` → **Identity → Roles & admins** should no longer be manageable.

---

## Step 9: Set up an Azure subscription

**Why:** Log Analytics (this phase), Azure custom roles (Phase 09), managed identities (Phase 10) and Sentinel (Phase 14) all need an Azure subscription in the DanotechInc tenant. Entra ID licences don't include one.

### 9a. Sign up

1. Sign in to a normal browser as **`daniel.opara@danotechinc.onmicrosoft.com`**. Billing ownership belongs with the business owner, which is also how you'd set it up in a real company.
2. Go to <https://azure.microsoft.com/free> → **Try Azure for free** / **Start free**.
3. Sign in with the same account when prompted. **This is the important part.** Signing up with a DanotechInc account puts the subscription in the DanotechInc tenant. Signing up with a personal Microsoft account would create it in a different directory.
4. Complete phone and card verification. The free account gives a $200 credit to use within 30 days and doesn't charge the card. Once the credit or the 30 days run out, the subscription is disabled unless you upgrade to pay-as-you-go.
5. In the [Azure portal](https://portal.azure.com), open **Subscriptions**, confirm the directory shown is **DanotechInc** and copy the **Subscription ID**.

> **Plan to upgrade to pay-as-you-go before the 30 days end.** The log pipeline must keep running for the rest of the program. At DanotechInc's volume, Log Analytics costs should stay small, and the budget in 9c will warn you well before anything significant. Check current prices on the [Azure Monitor pricing page](https://azure.microsoft.com/pricing/details/monitor/).

### 9b. Give the admin account access, and take it away from the daily account

**Why:** The person who signs up becomes subscription Owner. Azure administration should follow the same separation as Entra ID: the daily account keeps **billing** ownership (a business role), while the admin account gets the **technical** Owner role. Phase 09 replaces this broad Owner assignment with least-privilege custom roles and PIM.

1. **Subscriptions → (your subscription) → Access control (IAM) → Add → Add role assignment**.
2. Role: **Owner** (Privileged administrator roles tab) → Members: `adm.daniel.opara` → on the **Conditions** tab choose to allow all role assignments for now. Note it as a known gap: Phase 09 narrows this. → **Review + assign**.
3. Sign in to the portal as `adm.daniel.opara` and confirm you can see the subscription.
4. Back in **Access control (IAM) → Role assignments**, remove the **Owner** RBAC assignment from `daniel.opara`. Billing access is unaffected; it's a separate billing role.

### 9c. Set a budget alert

**Why:** With pay-as-you-go, a misconfigured diagnostic setting or a forgotten resource can quietly run up a bill. A budget alert turns surprise into an email.

**Cost Management → Budgets → Add**: name `budget-danotech-lab`, monthly, amount **$15**, alerts at 50%, 80% and 100% of actual cost, sent to your external email address.

Record the subscription ID and budget in `evidence/` (a screenshot is fine).

---

## Step 10: Create the automation identity

**Why:** From Phase 04 onwards, jobs run unattended: HR feed uploads, nightly reports, posture checks. They can't do interactive MFA, and running them as a person would mean storing that person's password. An app registration gives automation its own identity with its own sign-in log and only the permissions it's been granted.

- **Certificate, not secret.** A client secret is effectively a password in a file. With a certificate, the private key stays in your certificate store and only the public key goes to Entra ID.
- **Read-only to start.** Each later phase adds exactly the write permission it needs through a pull request, so the permission list is self-documenting.

**Windows:**
```powershell
./07-New-AutomationApp.ps1    # as adm.daniel.opara
```

**macOS / Linux:** create the certificate first, then pass the public key:
```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout automation.key -out automation.cer -subj "/CN=app-danotech-iam-automation"
cat automation.key automation.cer > automation.pem     # used by the Python script in Step 13
```
```powershell
./07-New-AutomationApp.ps1 -CertificatePath ./automation.cer
```
Keep these files **outside the repository**. `.gitignore` blocks `*.key`, `*.pem` and `*.cer` anyway, and push protection is the second line of defence.

Set the environment variables the script prints, then test app-only sign-in:

```powershell
$env:DANOTECH_AUTOMATION_CLIENT_ID = '<appId>'
$env:DANOTECH_AUTOMATION_CERT_THUMBPRINT = '<thumbprint>'
. ../../../scripts/common/Connect-Danotech.ps1
Connect-Danotech -AppOnly
(Get-MgContext).Scopes        # should list exactly the 4 read permissions
```

> **Certificate expiry:** the certificate is valid for 12 months. Phase 16 adds a check that flags app credentials expiring within 30 days.

---

## Step 11: Stream Entra ID logs to Log Analytics

**Why:** Entra ID keeps sign-in and audit logs for 30 days. Investigations and audit sampling need longer, and the detections in Phases 14–15 need the data in a workspace you can query with KQL. Starting the pipeline now means that by Phase 14 there's weeks of real history, including every change made in Phases 01–13.

```powershell
./08-Set-EntraDiagnosticSettings.ps1 -SubscriptionId '<your-subscription-id>'    # as adm.daniel.opara
```

This creates `rg-danotech-identity-prd-eus` and `log-danotech-identity-prd-eus` with 90-day retention and a 1 GB/day cap, then a tenant-level diagnostic setting that streams 11 log categories. The script comments explain which later phase uses each category.

**Microsoft Sentinel is deliberately not enabled yet.** Its free trial starts the day you enable it; enabling it in Phase 14, when you'll use it, gets the most from it.

Wait 15–30 minutes, then in the workspace (**Logs**) run [`kql/pipeline-health.kql`](kql/pipeline-health.kql). You should see `AuditLogs` (from the changes you made today) and `SigninLogs` (from your test sign-ins).

---

## Step 12: Alert on break-glass use

**Why:** A break-glass account should never sign in without a reason. Each sign-in is either a declared emergency or an incident, and either way the CISO and IAM Manager need to know within minutes. Alerting on **object IDs** rather than names means an attacker can't evade the alert by renaming the account.

1. Edit [`kql/breakglass-signin-alert.kql`](kql/breakglass-signin-alert.kql) and replace the two placeholder GUIDs with the object IDs from Step 2. Commit the change; object IDs aren't secrets.
2. Azure portal → **Monitor → Alerts → Create → Alert rule**.
3. **Scope:** `log-danotech-identity-prd-eus`.
4. **Condition:** *Custom log search* → paste the query → **Measurement:** Table rows, **Aggregation granularity** 5 minutes → **Alert logic:** greater than 0 → **Frequency** 5 minutes.
5. **Actions:** create action group `ag-danotech-security-critical` with an **Email** notification to your external address. (In production this would be the SOC distribution list and a paging service.)
6. **Details:** name `ALR-BreakGlass-SignIn`, severity **0 – Critical**, resource group `rg-danotech-identity-prd-eus`.
7. **Create.**

Repeat for [`kql/breakglass-change-audit.kql`](kql/breakglass-change-audit.kql) as `ALR-BreakGlass-Change` (severity 1, frequency 15 minutes). It catches tampering: password resets, method changes, role removal, or anyone being added to the exclusion group.

Log alert rules carry a small monthly charge each; two rules are well within the budget.

**Test:** sign in with break-glass 01 (this doubles as an access-log entry for the safe). Within about 10–15 minutes you should get the alert email. Save the email as `evidence/YYYYMMDD-breakglass-alert-test.png`.

---

## Step 13: Validate, capture evidence and merge

**Why:** A control isn't done until there's evidence it works. This step proves the end state and closes the Phase 01 issues with a reviewable pull request.

```powershell
./01-Get-TenantBaseline.ps1 -Label after
```

Run the Python report as the automation app. This also proves app-only authentication works from a second language:

```bash
cd ../python
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
export DANOTECH_AUTOMATION_CLIENT_ID='<appId>'
export DANOTECH_AUTOMATION_CERT_PATH='/path/outside/repo/automation.pem'   # or a .pfx exported from the Windows store
python tenant_baseline_report.py
```

Every check should report **PASS**, and the script exits non-zero if any fails, so it can later run in CI. Copy the report into `evidence/`.

### Validation checklist

- [ ] Two break-glass accounts sign in successfully with password + FIDO2 key
- [ ] What If shows **no** CA policies apply to break-glass accounts
- [ ] Credentials stored in two separate locations, with access logs
- [ ] `adm.daniel.opara` prompted for MFA; daily account has no admin roles
- [ ] Security defaults off; CA000, CA001, CA100 enabled
- [ ] Hardening settings applied (scripted and portal screenshots)
- [ ] Azure subscription in the DanotechInc directory, budget alert set, daily account not RBAC Owner
- [ ] Automation app signs in app-only with exactly 4 read permissions
- [ ] `pipeline-health.kql` returns data
- [ ] Break-glass sign-in alert received by email
- [ ] Python baseline report all PASS

### Commit

```bash
git checkout -b phase-01-tenant-foundation
git add phase-01-tenant-foundation/ docs/licensing.md
git commit -m "Phase 01: tenant foundation, break-glass, baseline CA, log pipeline"
git push -u origin phase-01-tenant-foundation
gh pr create --fill --milestone "Phase 01 Tenant foundation"
```

Before committing, open each evidence JSON and screenshot and check that no passwords, certificate private keys or personal email addresses are visible.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Insufficient privileges` when running a script | Consent was granted for different scopes earlier | `Disconnect-MgGraph`, then rerun so the new scopes are requested |
| Can't create CA policies: security defaults error | Security defaults still on | The script disables them first; check you ran it as a Global Admin |
| Role-assignable group creation fails | Missing `RoleManagement.ReadWrite.Directory` scope | Rerun script 02 after `Disconnect-MgGraph` |
| Break-glass sign-in asks for Authenticator, not FIDO2 | Passkey not registered for that account | Repeat Step 3 for that account |
| Diagnostic setting `403` | Account lacks Owner/Contributor on the subscription or Security Admin in Entra | Check Step 9b; use `adm.daniel.opara` |
| No data in Log Analytics after 30 min | Diagnostic setting not saved, or no activity yet | **Entra admin center → Monitoring → Diagnostic settings**; sign in once to generate events |
| Python `CertificateCredential` error | PEM missing the private key, or PFX password not set | Use the combined `automation.pem`, or set `DANOTECH_AUTOMATION_CERT_PASS` |

**Next:** [Phase 02: Identity source and HR data model](../phase-02-identity-data-model/)
