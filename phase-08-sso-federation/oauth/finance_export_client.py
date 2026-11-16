#!/usr/bin/env python3
"""
finance_export_client.py - OAuth 2.0 client credentials flow, with a certificate.

The scenario: Finance's month-end export job (app-danotech-finance-export) pulls every PAID expense
claim from the Danotech Expenses API. No user is involved, so it uses the client credentials grant:

  1. The app proves its identity to Entra ID with a CERTIFICATE (a signed client assertion).
     No client secret exists for this app.
  2. It asks for scope  api://<expenses app id>/.default  : "every application permission an admin
     has granted me on that API". Here that's exactly one: Claims.Read.All.
  3. Entra ID returns an access token whose `roles` claim contains Claims.Read.All and which has NO
     `scp` claim (that's how the API knows no user is involved).
  4. The API validates signature, issuer, audience and expiry, checks the role, and returns data.

Environment variables (never committed):
  DANOTECH_TENANT_ID        danotechinc.onmicrosoft.com
  FINANCE_EXPORT_CLIENT_ID  application (client) ID of app-danotech-finance-export
  FINANCE_EXPORT_CERT_PFX   path to the certificate + private key as a .pfx (outside the repo)
  FINANCE_EXPORT_CERT_PASS  the .pfx password (set it in the session; never in a file)
  EXPENSES_API_APP_ID       application (client) ID of app-danotech-expenses
  EXPENSES_API_BASE         e.g. https://danotech-expenses-xxxxx.azurewebsites.net

Usage
  python finance_export_client.py                 # paid claims as CSV on screen
  python finance_export_client.py --show-token    # also print the decoded access token claims
"""
import argparse
import base64
import csv
import json
import os
import sys

import msal
import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.serialization import pkcs12


def env(name):
    v = os.environ.get(name)
    if not v:
        sys.exit(f"Set {name} (see the docstring).")
    return v


def load_certificate(pfx_path, password):
    """Turn the .pfx exported from the Windows certificate store into what MSAL expects.
    The private key only ever exists in memory."""
    key, cert, _ = pkcs12.load_key_and_certificates(open(pfx_path, "rb").read(), password.encode())
    pem_key = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    return {"private_key": pem_key.decode(), "thumbprint": cert.fingerprint(hashes.SHA1()).hex()}


def decode_payload(token):
    part = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--status", default="Paid")
    ap.add_argument("--show-token", action="store_true")
    args = ap.parse_args()

    client = msal.ConfidentialClientApplication(
        env("FINANCE_EXPORT_CLIENT_ID"),
        authority=f"https://login.microsoftonline.com/{env('DANOTECH_TENANT_ID')}",
        client_credential=load_certificate(env("FINANCE_EXPORT_CERT_PFX"), env("FINANCE_EXPORT_CERT_PASS")),
    )
    result = client.acquire_token_for_client(scopes=[f"api://{env('EXPENSES_API_APP_ID')}/.default"])
    if "access_token" not in result:
        sys.exit(f"Token request failed: {result.get('error')}: {result.get('error_description')}")

    if args.show_token:
        claims = decode_payload(result["access_token"])
        keep = {k: claims.get(k) for k in ("aud", "iss", "azp", "roles", "scp", "ver", "exp")}
        print("Access token claims:", json.dumps(keep, indent=2), sep="\n")

    r = requests.get(f"{env('EXPENSES_API_BASE').rstrip('/')}/api/v1/claims", params={"status": args.status},
                     headers={"Authorization": f"Bearer {result['access_token']}"}, timeout=60)
    if r.status_code != 200:
        sys.exit(f"API returned {r.status_code}: {r.text}")
    rows = r.json()["claims"]
    if rows:
        w = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"\n{len(rows)} {args.status.lower()} claim(s) exported.", file=sys.stderr)


if __name__ == "__main__":
    main()
