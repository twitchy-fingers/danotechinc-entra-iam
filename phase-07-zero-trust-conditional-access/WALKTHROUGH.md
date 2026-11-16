# Phase 07 Walkthrough: Authentication and Zero Trust Conditional Access

**Goal:** Make passkeys the standard, lock admin accounts to phishing-resistant sign-in and admin tools, require a fresh passkey for Tier 0 PIM activation, add risk and location controls, and roll it all out safely through report-only and rings.

**When:** 23 November – 1 December 2026 (rings need a few days each).
**Time:** About 6 hours of work, spread over the rollout.
**Performed by:** Kofi Owusu and Adaeze Nwosu, with Oliver Hughes (CISO) approving each ring.

> ⚠️ **Lockout risk.** This phase can lock admins out if done out of order. The rules: break-glass is tested before you start; **every admin account has a passkey before CA100 is upgraded** (Step 8); new policies are report-only until you've read their impact (Step 9).

## Prerequisites

- Phase 06 complete: 14 admin accounts, PIM, `GRP-DYN-ALL-AdminAccounts`.
- Phase 01's Log Analytics workspace receiving sign-in logs (for the report-only KQL).
- Microsoft Authenticator holding the admin accounts' passkeys.

Scripts run from `phase-07-zero-trust-conditional-access\scripts\powershell\`, signed in as `adm.adaeze.nwosu` with **Conditional Access Administrator** activated (and **Privileged Role Administrator** for Step 10).

> **Signing in to Graph PowerShell with a passkey:** on Windows, `Connect-MgGraph` uses the Windows sign-in broker. If it can't offer the passkey, run `Set-MgGraphOption -DisableLoginByWAM $true` once to use the browser instead.

| Step | Where | What |
|---|---|---|
| 1 | Portal + script | Re-test break-glass; measure the starting point |
| 2 | Portal | Authentication methods: passkeys on, SMS and voice off |
| 3–5 | Portal | Named location, authentication strength, authentication context |
| 6 | Portal | Build CA002 by hand |
| 7 | Script | Deploy the other policies as report-only |
| 8 | Script + portal | Passkeys for every admin account |
| 9 | Portal + KQL | Read report-only impact; What If |
| 10 | Script + portal | Enforce admin policies; PIM authentication context |
| 11 | Portal | Enforce CA003 (registration) and CA300 (guests) |
| 12 | Script + portal | Workforce rings, with device code and risk tests |
| 13 | Script | Control test and evidence |

---

## Step 1: Re-test break-glass and measure the starting point

**Why:** Same rule as every high-risk phase: prove the way back in works before changing anything that can lock people out. Then measure, so the end of the phase has a "before" to compare with.

1. Sign in with **Emergency Access 02** (Phase 06 tested 01) and confirm Global Administrator works.
2. Run the adoption report:

```powershell
./04-Get-AuthMethodsReport.ps1
```

**Expected now:** AM-01 may pass (Phase 01 enabled FIDO2), **AM-02 FAIL** (SMS and voice still on), AM-03 pass. Adoption: break-glass 2/2 passkeys; admins 5 of 14 (the ones you registered in Phase 06); workforce mostly Authenticator push or nothing. The list of admin accounts **without** a passkey is your to-do list for Step 8.

---

## Step 2: Authentication methods: passkeys on, SMS and voice off

**Why:** Conditional Access can only ask for methods people are allowed to register. Passkeys need to be available to everyone; SMS and voice codes can be phished or stolen by SIM swap, so they go.

**Entra ID → Authentication methods → Policies**:

1. **Passkey (FIDO2)** → **Enable and Target:** Enable, **All users** → **Configure:** *Allow self-service set up* **Yes**; *Enforce attestation* **No** (lab: accepts Microsoft Authenticator and any security key); *Enforce key restrictions* **No** → **Save**.
2. **SMS** → **Disable** → **Save**. **Voice call** → **Disable** → **Save**.
3. **Microsoft Authenticator** stays enabled (it now holds passkeys too; number matching is always on).

Before disabling SMS in a real tenant, check the report from Step 1: anyone whose *only* method is SMS would be stuck. Here, nobody registered SMS.

Rerun `./04-Get-AuthMethodsReport.ps1`: AM-01, AM-02 and AM-03 all **PASS**.

---

## Step 3: Named location for the operating countries

**Why:** DanotechInc works in five countries. A sign-in from anywhere else is far more likely to be an attacker than a traveller, and the rare traveller can be handled with a time-limited exception (Phase 12).

**Entra ID → Conditional Access → Named locations → + Countries location**:
- **Name:** `NL-Operating-Countries` (exact; the script finds it by name)
- **Determine location by:** IP address (IPv4 and IPv6)
- Tick **United States, United Kingdom, Nigeria, Ghana, Mexico**
- **Include unknown countries/regions:** unticked
- **Create**

---

## Step 4: Custom authentication strength for registering security info

**Why:** Requiring a passkey to *register* a passkey is a chicken-and-egg problem for joiners. This strength allows what each kind of user actually has: a joiner's one-time TAP, an existing passkey, or (during the rollout only) password + Authenticator push for people who haven't moved to passkeys yet.

**Entra ID → Authentication methods → Authentication strengths → + New authentication strength**:
- **Name:** `AS-Onboarding-Passkey-or-TAP`
- **Description:** *Only for registering security info. Remove password + Authenticator push once passkey adoption is 100%.*
- Tick: **Temporary Access Pass (One-time use)**, **Passkeys (FIDO2)**, **Windows Hello For Business**, **Certificate-based authentication (Multifactor)**, **Microsoft Authenticator (Phone Sign-in)**, **Password + Microsoft Authenticator (Push Notification)**
- **Next → Create**

Open the built-in **Phishing-resistant MFA** strength next to it: only passkeys, Windows Hello and certificates. That's what CA100 and CA102 demand.

---

## Step 5: Authentication context for Tier 0 activation

**Why:** An authentication context is a label an application (here, PIM) can ask Conditional Access to satisfy *at a specific moment*, rather than at sign-in. It's how activation gets its own, stricter check.

**Entra ID → Conditional Access → Authentication contexts → + New authentication context**:
- **Name:** `Tier 0 privileged activation`
- **Description:** *Required when activating Global Administrator or Privileged Role Administrator.*
- **Publish to apps:** ✔ (without this, PIM can't select it)
- **ID:** `c1`
- **Save**

---

## Step 6: Build CA002 by hand

**Why:** Building one policy by hand teaches the four parts of every policy: *who*, *what*, *conditions*, *access controls*. The script then deploys the other nine and checks yours.

**Conditional Access → Policies → + New policy**:

| Section | Setting |
|---|---|
| Name | `CA002-AllUsers-AllApps-BlockOutsideOperatingCountries` |
| Users | Include **All users**; Exclude → Users and groups → `GRP-CA-Exclude-BreakGlass` |
| Target resources | **All resources** |
| Conditions → Locations | Configure **Yes**; Include **Any location**; Exclude → **Selected locations** → `NL-Operating-Countries` |
| Grant | **Block access** |
| Enable policy | **Report-only** |

**Create.** The *users* part changes when the policy moves through rings (Step 12); the script compares everything else.

---

## Step 7: Deploy the other policies (report-only)

```powershell
./01-Deploy-ConditionalAccess.ps1
```

**Expected:**
- `Created GRP-ASG-CA-Ring0` and `Created GRP-CA-Exclude-AdminOnboarding`
- `CA002-…: Exists, matches definition [enabledForReportingButNotEnforced]` (your portal work)
- **8 × Created (report-only):** CA003, CA004, CA101, CA102, CA103, CA200, CA201, CA300
- **`CA100-Admins-AllApps-RequireMFA: DIFFERS`**: the Phase 01 policy, listing exactly what changes: name, the admin accounts group, two extra roles, the onboarding exclusion, and *strength* instead of plain MFA. Leave it for now; Step 10 upgrades it.

If CA002 shows **DIFFERS**, the line names the field (for example `locEx is '', expected '<id>'`: the exclusion wasn't saved). Fix it in the portal and rerun.

---

## Step 8: Give every admin account a passkey

**Why:** CA100 will demand a phishing-resistant method from every admin account. An admin account without a passkey would be locked out the moment it's enforced, which is why this comes *before* Step 10.

Issue TAPs to the admin accounts still missing a passkey (the list from Step 1):

```powershell
$missing = 'diego.ramirez','emily.carter','priya.sharma','ashley.johnson','tobiloba.akinola','ximena.garcia','jamal.davis','carlos.gutierrez','babatunde.bakare' |
    ForEach-Object { "adm.$_@danotechinc.onmicrosoft.com" }
..\..\..\phase-04-jml-lifecycle\scripts\powershell\06-New-TemporaryAccessPass.ps1 -UserPrincipalName $missing
```

For each: private window → <https://aka.ms/mysecurityinfo> → TAP → **Add sign-in method → Passkey in Microsoft Authenticator**. Then:

```powershell
./04-Get-AuthMethodsReport.ps1
```

**Expected:** `Admin 14 enabled · passkey 14 (100%)` and no *WITHOUT a passkey* list. Don't continue until it says so.

> **New admin accounts later:** add the account to `GRP-CA-Exclude-AdminOnboarding`, register its passkey with a TAP, then remove it from the group the same day. The control test fails (CA-05) while the group isn't empty, so it can't be forgotten.

---

## Step 9: Read the report-only impact, and use What If

**Why:** Report-only policies are evaluated on every real sign-in and logged, but never enforced. Reading what they *would* have done is how you find the people a policy would break, before it breaks them.

### 9a. What If (portal)

**Conditional Access → Policies → What If**. Run these and note which policies apply (report-only policies appear in their own section):

| User | Resource / condition | Expected |
|---|---|---|
| `ADM - Daniel Opara` | App: **app-danotech-expenses** | **CA103** blocks (admin account, business app) |
| `ADM - Daniel Opara` | App: **Microsoft Admin Portals** | CA100, CA101 apply; CA103 does **not** |
| `ADM - Daniel Opara` | Authentication context: `c1` | **CA102** |
| `Kofi Owusu` (daily) | Any app; Country **France** | **CA002** blocks |
| `Kofi Owusu` | Any app; Sign-in risk **Medium** | **CA200** |
| `Emergency Access 01` | Any app; any condition | **No policies apply**. The most important check |

### 9b. Real sign-in impact (KQL)

Let a day of normal sign-ins happen (or sign in as a few personas from Phases 04–06). Then in **Log Analytics → log-danotech-identity-prd-eus → Logs**, run [`kql/report-only-impact.kql`](kql/report-only-impact.kql).

Read each row: *who would have been blocked or challenged, in which app, from where*. Expect CA103 rows for any admin account that touched a business app, and CA101 rows for long admin sessions. An unexpected row (for example a real user blocked by CA002 from an operating country) means the policy or a location is wrong. Fix it before enforcing.

The **Conditional Access → Insights and reporting** workbook shows the same data graphically. Open it and select a report-only policy.

---

## Step 10: Enforce the admin policies and the PIM authentication context

**Why:** Admin policies affect 14 known accounts, all now with passkeys, so they go straight to enforced. Tier 0 activation then starts demanding context `c1`.

1. Upgrade CA100 in place (it stays **On**, now demanding phishing-resistant MFA):

   ```powershell
   ./01-Deploy-ConditionalAccess.ps1 -UpdateExisting -Only CA100
   ```

   **Expected:** `CA100-Admins-AllApps-RequirePhishingResistantMFA: UPDATED [enabled]`. Immediately sign in to the admin center as `adm.kofi.owusu` in a private window: you'll be asked for the passkey, and push won't be offered.

2. Portal: set **CA101**, **CA102** and **CA103** to **On** (open each → **Enable policy: On** → **Save**).

3. As `adm.daniel.opara`, try to open the Danotech Expenses app (Phase 05). **Expected:** blocked by CA103. Admin accounts don't use business apps.

4. Apply the authentication context to Tier 0 PIM activation:

   ```powershell
   ./03-Set-PimAuthenticationContext.ps1
   ```

   **Expected:** both Tier 0 roles: *activation now requires authentication context c1 (+ justification, ticket, approval)*.

5. **Test it:** as `adm.daniel.opara` → **PIM → My roles → Global Administrator → Activate**. PIM asks you to sign in again with a passkey *before* the request is even submitted. Approve as Oliver Hughes. In **Sign-in logs**, the activation sign-in shows **Authentication requirement: c1**, method **Passkey**.

---

## Step 11: Enforce CA003 (registration) and CA300 (guests)

**Why:** CA003 decides how people prove themselves when adding a sign-in method, a favourite attacker move after stealing a password. CA300 has no guests to affect yet, so turning it on now means guests arrive into an already-enforced policy in Phase 12.

1. Test CA003 first: issue a TAP to **Valeria Morales** (Phase 04 joiner, 16 Nov) and register a passkey with it. In **Sign-in logs**, filter her user: the CA003 report-only result is *Success*, satisfied by the TAP.
2. Set **CA003** and **CA300** to **On**.

---

## Step 12: Roll out the workforce policies through the rings

**Why:** CA002, CA004, CA200 and CA201 affect everyone. Each ring is a group of people who can tell you if something's wrong, starting with the team that built it.

### Ring 0: the IAM team

```powershell
./02-Set-CaRolloutRing.ps1 -Ring 0
```

Answer `yes` once you've reviewed Step 9. Then test each policy as Kofi Owusu (daily account):

- **CA004, device code blocked:** `az login --use-device-code --tenant danotechinc.onmicrosoft.com`, then complete the code at the URL as `kofi.owusu@…`. **Expected:** blocked, *AADSTS53003*. (This is why Phase 01's Python report uses app-only sign-in, not `--interactive`, from now on.)
- **CA200, risky sign-in:** sign in to <https://myapps.microsoft.com> as Kofi using the **Tor Browser**, which ID Protection flags as an *anonymous IP address*. **Expected:** an extra MFA prompt. **ID Protection → Risky sign-ins** shows the detection; [`kql/risky-signins.kql`](kql/risky-signins.kql) shows CA200 applied.
- **CA201, high user risk:** **ID Protection → Risky users** → Kofi → **Confirm user compromised**. On his next sign-in: MFA, then a forced password change. Afterwards, **Dismiss user risk**.
- **CA002:** What If only (Step 9a). A real test would need travel.

### Rings 1 → 3

Leave a day or two between rings, re-running the report-only KQL each time, then:

```powershell
./02-Set-CaRolloutRing.ps1 -Ring 1     # + IT and Security
./02-Set-CaRolloutRing.ps1 -Ring 2     # + licensed cohort
./02-Set-CaRolloutRing.ps1 -Ring 3     # everyone
```

Each change is appended to `evidence\rollout-log.csv`: the audit trail of who widened which policy, when.

---

## Step 13: Control test, adoption and evidence

```powershell
./05-Test-ConditionalAccess.ps1 -Final
./04-Get-AuthMethodsReport.ps1
```

**Expected:** `PASS`, exit code `0`, and admin passkey adoption 100%.

`evidence\` should contain:
- `…-ca-policies.json`: every policy as deployed
- `…-auth-methods-adoption.csv`
- `rollout-log.csv`: every ring change
- Screenshots: the methods policy (Step 2), the What If for break-glass (Step 9), the report-only KQL result (Step 9), Kofi's passkey-only prompt (Step 10), the c1 activation sign-in (Step 10), the device-code block, the risky sign-in and the forced password change (Step 12)

Commit on a branch, PR to **Phase 07 Zero Trust Conditional Access**, label `risk:high`.

## Validation checklist

- [ ] Break-glass re-tested; What If shows no policies for it
- [ ] Passkeys on; SMS and voice off (AM-01 to AM-03 pass)
- [ ] Named location, authentication strength and context `c1` built in the portal
- [ ] CA002 built by hand and reported *matches definition*
- [ ] Every admin account has a passkey before CA100 was upgraded
- [ ] Report-only impact reviewed with KQL before enforcing
- [ ] CA100–CA103 enforced; admin account blocked from Expenses
- [ ] Tier 0 activation demands a fresh passkey (c1)
- [ ] Device code, risky sign-in and high user risk tested in Ring 0
- [ ] Workforce policies at Ring 3; rollout log complete
- [ ] Control test passes with `-Final`; PR merged

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Script 01: *Authentication context c1 not found* | Created but not **published to apps** | Tick *Publish to apps* (Step 5) |
| Policy creation rejected for CA103 | The `MicrosoftAdminPortals` value isn't accepted in an exclusion through the API in this tenant | Create CA103 with the other exclusions, then add **Microsoft Admin Portals** to *Exclude* in the portal; rerun script 01 to confirm |
| Admin account blocked from the Azure portal or PIM | CA103 exclusions missing an app | Sign-in log → *Conditional Access* tab shows the blocking policy and the app ID; add it to `adminAllowedApps` and redeploy |
| Admin can't sign in at all after Step 10 | No passkey registered | Break-glass → add the account to `GRP-CA-Exclude-AdminOnboarding` → TAP → passkey → remove it again |
| `Connect-MgGraph` can't use the passkey | Sign-in broker (WAM) limitation | `Set-MgGraphOption -DisableLoginByWAM $true` |
| Script 03: *CA102 must be ENABLED first* | Intentional guard | Step 10.2 |
| Python `--interactive` fails with AADSTS53003 | CA004 blocks device code flow | Use the app-only mode (Phase 01 Step 13) |
| No risk detected for the Tor sign-in | Detection can take minutes, or the exit node isn't flagged | Wait 10 minutes; try a new Tor circuit |
| Forced password change loops | User has no MFA method usable for the change | Ensure the user registered Authenticator or a passkey first |

**Next:** [Phase 08: SSO and federation](../phase-08-sso-federation/)
