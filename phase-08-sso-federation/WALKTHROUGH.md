# Phase 08 Walkthrough: SSO and Federation

**Goal:** Connect Salesforce and GitHub with SAML and SCIM, WordPress with OIDC and just-in-time admin, Keycloak as an identity broker, Okta as a federated partner, and a daemon calling the Expenses API with OAuth client credentials, then prove it all with a control test.

**When:** 30 November – 8 December 2026. The WordPress and Keycloak just-in-time admin steps need PIM, so finish them before 22 December.
**Time:** About 10–12 hours, in parts.
**Performed by:** Kofi Owusu, Diego Ramírez and Emily Carter, with each application's business owner.

## Prerequisites

| Need | For | How |
|---|---|---|
| Phases 05–07 complete | Everything | Groups, PIM groups, Conditional Access |
| Salesforce Developer Edition | Part B | Free sign-up at developer.salesforce.com |
| GitHub Enterprise Cloud trial | Part C | **30 days**: start it on the day you do Part C |
| Two personal GitHub accounts | Part C | Your own (plays Carlos Gutiérrez, the org owner) and one for Valeria Morales, registered with a plus-address of your inbox |
| Docker Desktop | Parts D, E | Running, with `docker compose version` working |
| Okta Integrator Free Plan org | Part F | Free sign-up at developer.okta.com |
| Your Azure subscription and GitHub repo | Part G | From Phases 01 and 05 |

All secrets created in this phase (client secrets, `.env` files, the certificate) go in `%USERPROFILE%\danotech-secrets\`, never in the repository. Scripts run from `phase-08-sso-federation\scripts\powershell\` as `adm.kofi.owusu` with **Application Administrator** activated (Phase 06). Portal menu names can shift slightly between releases; use the search box if a path doesn't match.

| Part | Integration | Pattern |
|---|---|---|
| A | Common setup | Pilot groups |
| B | Salesforce | SAML 2.0 + SCIM |
| C | GitHub Enterprise Cloud | SAML 2.0 + SCIM |
| D | WordPress | OIDC + just-in-time admin |
| E | Keycloak | Identity brokering |
| F | Okta | Federation between identity providers |
| G | Expenses API | OAuth 2.0 client credentials |
| H | Atlassian | Design review only |
| I | All | Allow-list, control test, evidence |

---

# Part A: Common setup

## Step 1: Create the pilot groups

**Why:** Salesforce Developer Edition, personal GitHub accounts and a partner's Okta org all limit how many users the lab can have. Pilot groups stand in for the production role groups and keep the rule *access only through groups*. GitHub's invitations and Okta's user matching also need an email address, so pilot members get a lab mail address.

```powershell
./01-New-PilotGroups.ps1 -Inbox you@outlook.com
```

**Expected:** three groups created with owners: `GRP-ASG-APP-Salesforce-Pilot` (Niamh Jones, Brandon Collins), `GRP-ASG-APP-GitHub-Pilot` (Carlos Gutiérrez, Valeria Morales), `GRP-ASG-APP-Okta-Kestrel-Pilot` (Lucía Herrera, Femi Okonkwo). Members without `mail` get one, for example `you+femi.okonkwo@outlook.com`.

---

# Part B: Salesforce (SAML 2.0 + SCIM)

## Step 2: Add Salesforce from the gallery and configure SAML

**Why:** Gallery apps come with Microsoft's tested templates for SAML and provisioning, so you configure values rather than build the integration.

1. In Salesforce: **Setup → My Domain**. Copy your domain, e.g. `danotech-dev-ed.develop.my.salesforce.com`.
2. [Entra admin center](https://entra.microsoft.com) → **Enterprise apps → New application** → search **Salesforce** → name `Salesforce - SSO` → **Create**.
3. **Properties:** *Assignment required?* **Yes**. **Owners:** add Fernanda Castillo (business owner) and Kofi Owusu.
4. **Single sign-on → SAML → Basic SAML Configuration → Edit**:
   - **Identifier (Entity ID):** `https://<your domain>`
   - **Reply URL (ACS):** `https://<your domain>`
   - **Sign on URL:** `https://<your domain>`
5. **Attributes & Claims:** confirm **Unique User Identifier (Name ID)** = `user.userprincipalname`. That's what Salesforce will match against each user's Federation ID.
6. **SAML Certificates → Federation Metadata XML → Download**.

## Step 3: Trust Entra ID in Salesforce

1. Salesforce **Setup → Single Sign-On Settings → Edit** → tick **SAML Enabled** → **Save**.
2. **New from Metadata File** → upload the XML from Step 2 → **Create**. Then:
   - **Name:** `Entra ID`
   - **SAML Identity Type:** *Assertion contains the Federation ID from the User object*
   - **SAML Identity Location:** *Identity is in the NameIdentifier element of the Subject statement*
   - **Entity ID:** `https://<your domain>` (must equal Step 2's Identifier)
   - **Save**.
3. **Setup → My Domain → Authentication Configuration → Edit** → tick **Entra ID**. Keep **Login Form** ticked too: your own Salesforce admin keeps a local login as the app's break-glass. **Save**.

## Step 4: Connect provisioning (SCIM) and provision on demand

**Why:** SSO lets people in; it doesn't remove anyone. Provisioning creates Salesforce users when someone is assigned and deactivates them when they leave, which closes finding F-02 for Salesforce.

1. Salesforce: **Setup → Company Information → User Licenses**. Note how many *Salesforce* licences are free; the pilot needs two.
2. Entra: **Salesforce - SSO → Provisioning → Get started → Provisioning Mode: Automatic**.
3. **Admin Credentials:** enter what the page asks for: either **Authorize** and sign in as your Salesforce admin, or your admin username, password and **security token** (Salesforce: your avatar → **Settings → Reset My Security Token**; it's emailed). **Test Connection → Save**.
4. **Mappings → Provision Microsoft Entra ID Users**: check **userPrincipalName → FederationIdentifier** and **appRoleAssignments → ProfileName** are present.
5. **Settings → Scope:** *Sync only assigned users and groups*. **Provisioning Status: On → Save**.
6. After a few minutes the app's roles are imported from Salesforce's profiles. **Users and groups → Add user/group** → `GRP-ASG-APP-Salesforce-Pilot` → role **Standard User** → **Assign**.
7. Don't wait 40 minutes for a cycle: **Provisioning → Provision on demand** → **Niamh Jones** → **Provision**. Read each step: *Import user*, *Determine if user is in scope*, *Match user between source and target* (no match), *Perform action* (**Create**). Repeat for Brandon Collins.

**Check in Salesforce:** **Setup → Users** lists Niamh Jones and Brandon Collins, profile *Standard User*, **Federation ID** = their UPN.

## Step 5: Sign in, then deprovision

1. Private window → `https://<your domain>` → **Entra ID** → sign in as **Niamh Jones** (passkey). You're in Salesforce, no Salesforce password involved.
2. Same as **Femi Okonkwo** (not in the pilot). **Expected:** Entra ID refuses with **AADSTS50105**.
3. **Deprovision:** remove Brandon Collins from `GRP-ASG-APP-Salesforce-Pilot`, then **Provision on demand** for him. **Expected:** action **Update**, setting *IsActive = false*. In Salesforce, Brandon's user is **inactive**. Salesforce never deletes users, so history is preserved. Add him back afterwards.

Screenshot the on-demand steps (create and disable) and the Salesforce user list for `evidence\`.

---

# Part C: GitHub Enterprise Cloud (SAML 2.0 + SCIM)

## Step 6: Start the trial and add the gallery app

1. Start a **GitHub Enterprise Cloud trial** (github.com → your profile → **Your organizations → New organization**, choose the Enterprise trial). Name the organization, e.g. `danotechinc-lab`. **The trial lasts 30 days.**
2. Entra: **Enterprise apps → New application** → **GitHub Enterprise Cloud - Organization** → name `GitHub - SSO` → **Create**. Assignment required **Yes**; owners Carlos Gutiérrez and Emily Carter.
3. **Single sign-on → SAML → Basic SAML Configuration**:
   - **Identifier:** `https://github.com/orgs/<org>`
   - **Reply URL:** `https://github.com/orgs/<org>/saml/consume`
   - **Sign on URL:** `https://github.com/orgs/<org>/sso`
4. Name ID stays `user.userprincipalname` (it must equal the SCIM `userName` later).
5. Copy the **Login URL** and **Microsoft Entra Identifier**; download **Certificate (Base64)**.
6. **Users and groups:** assign `GRP-ASG-APP-GitHub-Pilot` (role **User**).

## Step 7: Enable SAML in the GitHub organization

1. GitHub organization → **Settings → Authentication security → Enable SAML authentication**:
   - **Sign on URL:** the Login URL
   - **Issuer:** the Microsoft Entra Identifier
   - **Public certificate:** paste the Base64 certificate
   - Signature method **RSA-SHA256**
2. **Test SAML configuration**. You're sent to Entra ID: sign in as **Carlos Gutiérrez**. Your GitHub account (the org owner) is now linked to Carlos's identity. **Save**.

Don't tick *Require SAML SSO* until Step 8 works; enforcing too early can lock members out.

## Step 8: Provision with SCIM, link Valeria, then remove her

1. Entra: **GitHub - SSO → Provisioning → Automatic** → **Tenant URL:** `https://api.github.com/scim/v2/organizations/<org>` → **Authorize** (sign in to GitHub as the org owner) → **Test Connection → Save**. Scope **assigned users and groups**, status **On**.
2. **Provision on demand → Valeria Morales**. GitHub emails an invitation to her plus-address.
3. Signed in to GitHub as **Valeria's** account, accept the invitation, then open `https://github.com/orgs/<org>/sso` and sign in to Entra ID as **Valeria Morales**. Her GitHub account is now linked to her Entra identity: organization **People → Valeria → SAML identity linked**.
4. Now tick **Require SAML SSO for all members** (organization settings).
5. **Deprovision:** remove Valeria from `GRP-ASG-APP-GitHub-Pilot` → **Provision on demand**. **Expected:** she's **removed from the organization**. Re-add her afterwards.

**Optional: team sync.** Organization **Settings → Team synchronization → Microsoft Entra ID**, then create a team `platform` linked to `GRP-DYN-JOB-ENG-PLATFORM`. Team membership then follows HR job codes.

---

# Part D: WordPress (OIDC + just-in-time admin)

## Step 9: Run WordPress

```powershell
cd ..\..\wordpress
New-Item -ItemType Directory "$HOME\danotech-secrets" -Force | Out-Null
Copy-Item .env.example "$HOME\danotech-secrets\wordpress.env"
"WP_DB_PASSWORD=$([Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(20)))" |
    Set-Content "$HOME\danotech-secrets\wordpress.env"
docker compose --env-file "$HOME\danotech-secrets\wordpress.env" up -d
```

Open <http://localhost:8081> and complete the installer. The admin you create here (call it `wp-breakglass`, long random password) is WordPress's **break-glass**: store it like Phase 01's credentials and never use it day to day.

Then **Settings → Permalinks → Post name → Save** (the OIDC plugin's redirect URI needs pretty permalinks), and **Plugins → Add New** → install and activate **OpenID Connect Generic Client**. **Plugins → Must-Use** lists *DanotechInc Entra ID role mapping*, mounted read-only from this repo.

## Step 10: Register WordPress in Entra ID

1. **App registrations → New registration:** `app-danotech-wordpress`, single tenant, redirect **Web** `http://localhost:8081/openid-connect-authorize` → **Register**.
2. **App roles:** create three, allowed member types **Users/Groups**:

   | Display name | Value |
   |---|---|
   | WordPress author | `WordPress.Author` |
   | WordPress editor | `WordPress.Editor` |
   | WordPress administrator (just-in-time) | `WordPress.Admin` |

3. **API permissions:** add Microsoft Graph delegated `openid`, `profile`, `email` → **Grant admin consent**.
4. **Certificates & secrets:** new client secret, **30 days**; copy the value.
5. **Enterprise apps → app-danotech-wordpress → Properties:** assignment required **Yes**; owners Ngozi Balogun and Diego Ramírez. **Users and groups:** assign `GRP-DYN-JOB-MKT-WEB` → **WordPress editor** (your first assignment), then let the script do the rest:

```powershell
cd ..\scripts\powershell
./02-Set-AppRoleAssignments.ps1 -App wordpress
```

**Expected:** `exists GRP-DYN-JOB-MKT-WEB -> WordPress.Editor`, `added GRP-DYN-JOB-MKT -> WordPress.Author`, `added GRP-ROLE-PIM-WP-ADMIN -> WordPress.Admin`.

## Step 11: Configure the OIDC plugin

WordPress → **Settings → OpenID Connect Client**:

| Setting | Value | Why |
|---|---|---|
| Login Type | OpenID Connect button on login form | Keeps the local break-glass login available |
| Client ID / Client Secret Key | From Step 10 | |
| OpenID Scope | `openid email profile` | |
| Login Endpoint URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` | |
| **Userinfo Endpoint URL** | **leave empty** | The plugin then reads identity from the ID token, which carries `preferred_username` and `roles`; Microsoft's userinfo endpoint carries neither |
| Token Validation Endpoint URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` | |
| End Session Endpoint URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/logout` | |
| Identity Key / Nickname Key | `preferred_username` | The UPN: stable and unique |
| Email Formatting | `{preferred_username}` | Not every user has a mail attribute |
| Display Name Formatting | `{name}` | |
| Create user if does not exist | ✔ | Accounts appear on first sign-in |
| Alternate Redirect URI | ✔ | Matches the redirect URI in Step 10 |

**Save**.

## Step 12: Sign in, and make Ngozi admin just-in-time

1. Register Ngozi's admin account in CA103's allow-list first (admin accounts are otherwise blocked from business apps):

   ```powershell
   ./04-Update-AdminAllowedApps.ps1
   ```

   It redeploys CA103 through the Phase 07 script, so activate **Conditional Access Administrator** as well. Run it again after Part E so Keycloak is added too.
2. Private window → <http://localhost:8081/wp-login.php> → **Login with OpenID Connect** → sign in as **Ngozi Balogun** (daily account). **Users** in WordPress shows her as **Editor**: she's in `GRP-DYN-JOB-MKT-WEB`.
3. As **`adm.ngozi.balogun`**: **PIM → My roles → Groups → GRP-ROLE-PIM-WP-ADMIN → Activate** (Phase 06 Step 12), 1 hour.
4. New private window → WordPress → sign in as `adm.ngozi.balogun`. **Expected:** **Administrator**. The container log shows the mapping: `docker compose logs wordpress | Select-String danotech-entra-roles`.
5. **Deactivate** the PIM membership, sign out, sign in again as `adm.ngozi.balogun`. **Expected:** **Subscriber**. Admin rights ended without anyone touching WordPress.

---

# Part E: Keycloak (identity brokering)

## Step 13: Run Keycloak and create the realm

```powershell
cd ..\..\keycloak
Copy-Item .env.example "$HOME\danotech-secrets\keycloak.env"
notepad "$HOME\danotech-secrets\keycloak.env"     # set a long random password
docker compose --env-file "$HOME\danotech-secrets\keycloak.env" up -d
```

Open <http://localhost:8080/admin> and sign in with the bootstrap admin. Then:
1. **Create realm:** `danotech-partners`.
2. **Realm roles → Create role:** `portal-agent`.
3. **Users → Add user:** `partner.alex@kestrel.example`, set a password under **Credentials**. A partner with a *local* account: Keycloak still serves its own users.

## Step 14: Register the broker in Entra ID

1. **App registrations → New registration:** `app-danotech-keycloak-broker`, single tenant, redirect **Web** `http://localhost:8080/realms/danotech-partners/broker/entra-id/endpoint`.
2. **App roles:** `Partner portal agent` / `Portal.Agent`, and `Partner portal realm administrator (just-in-time)` / `Realm.Admin`.
3. API permissions `openid`, `profile`, `email` with admin consent; client secret, 30 days.
4. Enterprise app: assignment required **Yes**; owners Lucía Herrera and Kofi Owusu; assign `GRP-DYN-JOB-CS` → **Partner portal agent**. Then:

```powershell
cd ..\scripts\powershell
./02-Set-AppRoleAssignments.ps1 -App keycloak
./04-Update-AdminAllowedApps.ps1
```

## Step 15: Add Entra ID as an identity provider in Keycloak

Realm `danotech-partners` → **Identity providers → OpenID Connect v1.0**:

| Setting | Value | Why |
|---|---|---|
| Alias | `entra-id` | Must match the redirect URI path |
| Display name | `DanotechInc staff (Entra ID)` | The button partners and staff see |
| Discovery endpoint | `https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration` | Fills in every endpoint and the signing keys |
| Client authentication | Client secret sent as post | |
| Client ID / Secret | From Step 14 | |
| Default scopes | `openid profile email` | |
| Sync mode (advanced) | **Force** | Roles and details are re-applied at every login, so movers and leavers never keep stale roles |

**Save**. Then **Mappers → Add mapper**, three times:

| Name | Type | Settings |
|---|---|---|
| `username` | Username Template Importer | Template `${CLAIM.preferred_username}` |
| `portal-agent` | Claim to Role | Claim `roles`, value `Portal.Agent`, role `portal-agent` |
| `realm-admin` | Claim to Role | Claim `roles`, value `Realm.Admin`, role `realm-management` → `realm-admin` |

## Step 16: Test brokered sign-in

1. Private window → <http://localhost:8080/realms/danotech-partners/account> → **DanotechInc staff (Entra ID)** → sign in as **Femi Okonkwo** (Customer Success Manager). On first login Keycloak may ask you to confirm profile details; then the account console opens.
2. Admin console → **Users → femi.okonkwo@…** → **Role mapping:** `portal-agent`. **Identity provider links:** `entra-id`. Femi has no Keycloak password.
3. The same page with `partner.alex@kestrel.example` and its local password: a partner signs in without Entra ID at all.
4. **Just-in-time realm admin:** as `adm.kofi.owusu`, activate `GRP-ROLE-PIM-KC-ADMIN` in PIM, then sign in through the broker at <http://localhost:8080/admin/danotech-partners/console>. **Expected:** the realm admin console opens. After deactivation and a fresh login: access denied.

---

# Part F: Okta (federation with a partner's identity provider)

## Step 17: Register Okta in Entra ID

1. Sign up for an **Okta Integrator Free Plan** org; note its URL (`https://<org>.okta.com`).
2. **App registrations → New registration:** `app-danotech-okta-federation`, single tenant, redirect **Web** `https://<org>.okta.com/oauth2/v1/authorize/callback`.
3. **Token configuration → Add optional claim → ID → email**. Okta matches users on email.
4. **App roles:** `Kestrel Logistics portal user` / `Kestrel.User`. API permissions `openid`, `profile`, `email` with admin consent. Client secret, 30 days.
5. Enterprise app: assignment required **Yes**; owners Lucía Herrera and Kofi Owusu; assign `GRP-ASG-APP-Okta-Kestrel-Pilot` → **Kestrel Logistics portal user**.
6. Copy your **Directory (tenant) ID** from the app's Overview.

## Step 18: Trust DanotechInc in Okta

Okta Admin Console → **Security → Identity Providers → Add identity provider → OpenID Connect IdP**:

| Setting | Value |
|---|---|
| Name | `DanotechInc Entra ID` |
| Client ID / Secret | From Step 17 |
| Scopes | `openid profile email` |
| Issuer | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| Authorization endpoint | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` |
| Token endpoint | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| JWKS endpoint | `https://login.microsoftonline.com/<tenant-id>/discovery/v2.0/keys` |
| IdP username | `idpuser.email` |
| If no match is found | Create new user (JIT) |

**Save**. Then **Security → Identity Providers → Routing rules → Add routing rule:** *DanotechInc staff*, **User matches** domain `danotechinc.onmicrosoft.com` → **Use this identity provider:** DanotechInc Entra ID → **Activate**.

## Step 19: Test the federation

1. Private window → `https://<org>.okta.com` → enter `lucia.herrera@danotechinc.onmicrosoft.com`. The routing rule sends you to Entra ID; sign in with her passkey. **Expected:** the Okta End-User Dashboard.
2. Okta Admin → **Directory → People:** Lucía exists, created just in time, source **DanotechInc Entra ID**. Kestrel never stored a password for her.
3. Repeat with **Niamh Jones** (not in the pilot). **Expected:** Entra ID refuses (AADSTS50105) before Okta sees anything. DanotechInc decides who federates.

---

# Part G: OAuth 2.0 client credentials (Finance export → Expenses API)

## Step 20: Expose the Expenses API

**Why:** An API needs its own identity and permissions before anything can be granted access to it. The Expenses app already has an app registration (Phase 05); this step makes it an API too.

**App registrations → app-danotech-expenses**:
1. **Expose an API → Application ID URI → Add** → accept `api://<client id>` → **Save**.
2. **Add a scope:** `Claims.Read`, *Admins only*, display name *Read expense claims as the signed-in user* (used in Phase 11).
3. **App roles → Create app role:** display name *Read all expense claims*, **Allowed member types: Applications**, value `Claims.Read.All`. This is an *application permission*: granted to software, not people.
4. **Manifest:** set `"requestedAccessTokenVersion": 2` in the `api` section (older manifests: `"accessTokenAcceptedVersion": 2`) → **Save**. The API validates v2 tokens, whose issuer includes the tenant ID.

## Step 21: Register the finance export job with a certificate

1. **App registrations → New registration:** `app-danotech-finance-export`, single tenant, **no redirect URI** (nobody signs in to it).
2. Create its certificate (private key stays on your PC):

   ```powershell
   $cert = New-SelfSignedCertificate -Subject 'CN=app-danotech-finance-export' -CertStoreLocation Cert:\CurrentUser\My `
       -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -NotAfter (Get-Date).AddMonths(6)
   $pfxPass = Read-Host -AsSecureString 'Password for the PFX file'
   Export-PfxCertificate -Cert $cert -FilePath "$HOME\danotech-secrets\finance-export.pfx" -Password $pfxPass | Out-Null
   Export-Certificate -Cert $cert -FilePath "$HOME\danotech-secrets\finance-export.cer" | Out-Null
   ```

3. **Certificates & secrets → Certificates → Upload certificate** → `finance-export.cer` (public key only).
4. **API permissions → Add a permission → APIs my organization uses → app-danotech-expenses → Application permissions → Claims.Read.All → Add** → **Grant admin consent**.
5. Enterprise app: owners Rachel Okafor and Emily Carter.

## Step 22: Release the updated Expenses app

The API endpoint is new code in `phase-05-groups-app-roles/app/app.py` (and `requirements.txt` gains `pyjwt`). Merge this phase's PR into `main`, then on GitHub open a pull request from `main` into `release/expenses` and merge it. Deployment Center (Phase 05) builds and deploys it. Check the **Actions** run is green.

## Step 23: Run the export, then take its permission away

```powershell
cd ..\..\oauth
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:DANOTECH_TENANT_ID = 'danotechinc.onmicrosoft.com'
$env:FINANCE_EXPORT_CLIENT_ID = '<app-danotech-finance-export client id>'
$env:FINANCE_EXPORT_CERT_PFX = "$HOME\danotech-secrets\finance-export.pfx"
$env:FINANCE_EXPORT_CERT_PASS = Read-Host 'PFX password'
$env:EXPENSES_API_APP_ID = '<app-danotech-expenses client id>'
$env:EXPENSES_API_BASE = 'https://<your app>.azurewebsites.net'
python finance_export_client.py --show-token
```

**Expected:**
- Access token claims: `aud` = the Expenses client ID, `roles` = `["Claims.Read.All"]`, **no `scp`**, `ver` = `2.0`, `azp` = the finance export client ID.
- The paid claims from Phase 05's demo (Niamh's client dinner) as CSV.

**Take the permission away:** **app-danotech-finance-export → API permissions → Claims.Read.All → Revoke admin consent**. Run the script again. **Expected:** Entra ID still issues a token (the app is genuine), but without the role, and the API answers **403 insufficient_scope**. Grant consent again afterwards.

Sign in to the Expenses app as **Nana Agyeman** → **Audit**: the activity log shows *app finance-export* API calls, both *Success* and *Denied*.

---

# Part H: Atlassian Cloud (design review)

## Step 24: Confirm the blocker and record the design

**Why:** Pretending an integration works is worse than documenting why it can't. An auditor accepts a known, explained gap; they don't accept a false claim.

1. In your Atlassian site: **admin.atlassian.com → Security → Identity providers** (or **Directory → Domains**). SAML can only be applied to accounts on a **verified domain**, verified by DNS record or HTML file. `danotechinc.onmicrosoft.com` belongs to Microsoft, so DanotechInc can't verify it.
2. Screenshot the domain verification requirement for `evidence\`.
3. Review the documented design in the README's [Atlassian section](README.md#atlassian-cloud-designed-blocked). It's recorded in [ADR-0014](../docs/adr/0014-sso-and-federation-design.md) as a known gap.

---

# Part I: Verify everything

## Step 25: Control test and evidence

```powershell
cd ..\scripts\powershell
./02-Set-AppRoleAssignments.ps1          # every app: nothing missing, nothing extra
./03-Test-FederatedApps.ps1
"Exit code: $LASTEXITCODE"
./05-Get-Phase08Evidence.ps1
```

**Expected:** `PASS`, exit code `0`. The client secrets (WordPress, Keycloak, Okta, and Expenses from Phase 05) are listed as *notes* with their expiry dates: Phase 10 replaces them.

In **Log Analytics**, run [`kql/federation-signins.kql`](kql/federation-signins.kql) (sign-ins per app, user vs app-only) and [`kql/assignment-refusals.kql`](kql/assignment-refusals.kql) (the AADSTS50105 refusals from Steps 5 and 19).

`evidence\` should contain:
- `…-federated-apps.csv`, `…-federated-signins.csv`, `…-outbound-provisioning.csv`, `…-federated-apps-test.csv`
- Screenshots: Salesforce on-demand create and disable; GitHub SAML identity linked and member removed; WordPress Editor → Administrator → Subscriber; Keycloak role mapping and identity provider link; Okta JIT user; the finance export token claims and the 403 after revoking consent; the Atlassian domain requirement

Commit on a branch and open a PR to **Phase 08 SSO and federation**. It changes the Phase 05 app and the Phase 07 config (CA103 allow-list), so label it `risk:high`.

## Validation checklist

- [ ] Pilot groups created with owners; pilot members have mail
- [ ] Salesforce: SAML sign-in; SCIM create and deactivate; non-pilot refused
- [ ] GitHub: SAML linked; SCIM invite and removal; SAML SSO required
- [ ] WordPress: Editor from groups; Administrator only while PIM is active
- [ ] Keycloak: brokered staff login with roles; local partner login; just-in-time realm admin
- [ ] Okta: routing rule sends DanotechInc staff to Entra ID; JIT user; non-pilot refused
- [ ] Finance export: certificate-only client; token has the role, no `scp`; 403 after revoking consent
- [ ] Atlassian blocker evidenced and recorded
- [ ] CA103 allow-list updated through the Phase 07 config
- [ ] Control test passes; evidence exported; PR merged

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Salesforce: *We can't log you in because of an issue with single sign-on* | Federation ID not set, or Entity ID mismatch | Check the user's Federation ID equals the UPN; Salesforce **SAML Assertion Validator** (Single Sign-On Settings) shows the exact failure |
| Salesforce provisioning *Test Connection* fails | Wrong security token, or the admin lacks API access | Reset the token; Developer Edition admins have API access by default |
| No roles to pick when assigning Salesforce | Provisioning not connected yet | Step 4.3 first: roles are imported from Salesforce profiles |
| GitHub: *SAML response invalid* | Certificate or Issuer pasted wrongly | Re-copy from the app's SAML page; signature method RSA-SHA256 |
| GitHub SCIM *Test Connection* fails | Authorized as a non-owner, or SAML not enabled at organization level | Authorize as an owner; Step 7 first |
| GitHub member not linked after SCIM | NameID and SCIM `userName` differ | Both must be `userPrincipalName` |
| WordPress *invalid redirect URI* (AADSTS50011) | Alternate Redirect URI not ticked, or permalinks plain | Step 9 permalinks, Step 11 Alternate Redirect URI |
| WordPress user created but role never changes | Userinfo endpoint filled in, or token response not stored | Clear Userinfo Endpoint URL; `docker compose logs wordpress` for `danotech-entra-roles` lines |
| Admin account blocked from WordPress or Keycloak (AADSTS53003) | CA103 allow-list not updated | `./04-Update-AdminAllowedApps.ps1` |
| Keycloak: *Invalid parameter: redirect_uri* at Entra ID | Alias isn't `entra-id`, or URI differs | The alias is part of the redirect URI |
| Keycloak role not applied | Sync mode not Force, or claim value case differs | Sync mode **Force**; values are case-sensitive. If `Claim to Role` doesn't match the array claim, use **Advanced Claim to Role** with claim `roles` |
| Okta: *The issuer doesn't match* | Issuer must contain the tenant **ID**, not the domain name | Use the GUID from the app's Overview |
| Okta creates no user | No `email` in the token | Step 17.3 optional claim; pilot members need `mail` (Step 1) |
| Finance export: `AADSTS700027` | Certificate not uploaded, or wrong PFX | Upload the matching `.cer` (Step 21.3) |
| API returns `invalid_token` / `InvalidIssuerError` | v1 tokens issued | Step 20.4: `requestedAccessTokenVersion` 2; get a new token |
| API returns `insufficient_scope` with consent granted | Token cached from before the grant | Wait a few minutes; MSAL caches tokens per run only |

**Next:** [Phase 09: Cloud IAM](../phase-09-cloud-iam/)
