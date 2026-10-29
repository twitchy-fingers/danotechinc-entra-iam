#!/usr/bin/env python3
"""
tenant_baseline_report.py - Phase 01 posture report, run as the automation app.

Why this exists: it proves the automation identity from Step 10 works end to
end (certificate auth, app-only token, least-privilege read permissions) and
produces a Markdown posture summary you can paste into a PR or evidence folder.

Authentication
  Default : app-only, using app-danotech-iam-automation and its certificate
            (PEM or PFX). No user is involved and no secret is stored.
  --interactive : device-code sign-in as an admin, for when the app isn't set up yet.

Environment variables (app-only)
  DANOTECH_AUTOMATION_CLIENT_ID   app (client) ID of app-danotech-iam-automation
  DANOTECH_AUTOMATION_CERT_PATH   path to the certificate with private key (.pem or .pfx)
  DANOTECH_AUTOMATION_CERT_PASS   PFX password, if any (never put it in the repo)

Usage
  python tenant_baseline_report.py                 # app-only
  python tenant_baseline_report.py --interactive   # device code
"""
import argparse
import datetime as dt
import os
import sys
from pathlib import Path

import requests
from azure.identity import CertificateCredential, DeviceCodeCredential

TENANT = "danotechinc.onmicrosoft.com"
GRAPH = "https://graph.microsoft.com/v1.0"
# Microsoft Graph Command Line Tools public client, used only for --interactive
GRAPH_CLI_CLIENT_ID = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
GA_ROLE = "62e90394-69f5-4237-9190-012177145e10"


def get_token(interactive: bool) -> str:
    if interactive:
        cred = DeviceCodeCredential(tenant_id=TENANT, client_id=GRAPH_CLI_CLIENT_ID)
        scopes = ["Directory.Read.All", "Policy.Read.All", "RoleManagement.Read.Directory"]
        return cred.get_token(*[f"https://graph.microsoft.com/{s}" for s in scopes]).token
    client_id = os.environ.get("DANOTECH_AUTOMATION_CLIENT_ID")
    cert_path = os.environ.get("DANOTECH_AUTOMATION_CERT_PATH")
    if not client_id or not cert_path:
        sys.exit("Set DANOTECH_AUTOMATION_CLIENT_ID and DANOTECH_AUTOMATION_CERT_PATH, or use --interactive.")
    cred = CertificateCredential(
        tenant_id=TENANT, client_id=client_id, certificate_path=cert_path,
        password=os.environ.get("DANOTECH_AUTOMATION_CERT_PASS"),
    )
    # App-only tokens always use the /.default scope: the token carries
    # exactly the application permissions an admin granted, nothing more.
    return cred.get_token("https://graph.microsoft.com/.default").token


def graph_get(session: requests.Session, path: str) -> list | dict:
    url, items = f"{GRAPH}/{path}", []
    while url:
        r = session.get(url, timeout=30)
        r.raise_for_status()
        data = r.json()
        if "value" not in data:
            return data
        items.extend(data["value"])
        url = data.get("@odata.nextLink")
    return items


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--interactive", action="store_true")
    ap.add_argument("--out", default="output")
    args = ap.parse_args()

    s = requests.Session()
    s.headers["Authorization"] = f"Bearer {get_token(args.interactive)}"

    sd = graph_get(s, "policies/identitySecurityDefaultsEnforcementPolicy")
    authz = graph_get(s, "policies/authorizationPolicy")
    ca = graph_get(s, "identity/conditionalAccess/policies")
    ga = graph_get(s, f"roleManagement/directory/roleAssignments?$filter=roleDefinitionId eq '{GA_ROLE}'&$expand=principal")

    perms = authz.get("defaultUserRolePermissions", {})
    checks = [
        ("Security defaults replaced by CA", not sd.get("isEnabled"), f"isEnabled={sd.get('isEnabled')}"),
        ("Baseline CA policies enabled", sum(p["state"] == "enabled" for p in ca) >= 3, f"{len(ca)} policies"),
        ("Users cannot register apps", perms.get("allowedToCreateApps") is False, ""),
        ("Users cannot consent to apps", not perms.get("permissionGrantPoliciesAssigned"), ""),
        ("Users cannot create tenants", perms.get("allowedToCreateTenants") is False, ""),
        ("Guest invites restricted", authz.get("allowInvitesFrom") == "adminsAndGuestInviters", authz.get("allowInvitesFrom", "")),
        ("Global Admin count between 3 and 5", 3 <= len(ga) <= 5, f"{len(ga)} holders"),
        ("CEO daily account has no Global Admin",
         not any(a["principal"].get("userPrincipalName", "").startswith("daniel.opara@") for a in ga), ""),
    ]

    now = dt.datetime.now(dt.timezone.utc)
    lines = [f"# DanotechInc tenant baseline - {now:%Y-%m-%d %H:%M} UTC", "",
             "| Check | Result | Detail |", "|---|---|---|"]
    lines += [f"| {name} | {'PASS' if ok else 'FAIL'} | {detail} |" for name, ok, detail in checks]
    lines += ["", "## Global Administrators", ""]
    lines += [f"- {a['principal'].get('userPrincipalName', a['principal'].get('displayName'))}" for a in ga]
    lines += ["", "## Conditional Access", ""]
    lines += [f"- `{p['displayName']}`: {p['state']}" for p in sorted(ca, key=lambda p: p["displayName"])]

    out = Path(args.out)
    out.mkdir(exist_ok=True)
    f = out / f"{now:%Y%m%d}-baseline-report.md"
    f.write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))
    print(f"\nWritten to {f}")
    sys.exit(0 if all(ok for _, ok, _ in checks) else 1)


if __name__ == "__main__":
    main()
