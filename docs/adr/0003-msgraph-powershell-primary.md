# ADR-0003: Microsoft Graph PowerShell SDK as primary automation tool

- **Status:** Accepted
- **Date:** 2026-10-27
- **Deciders:** Adaeze Nwosu (IAM Manager), Kofi Owusu (Senior IAM Engineer)
- **Phase:** 00

## Context
Configuration must be repeatable and reviewable in Git. The legacy AzureAD and MSOnline modules are retired.

## Decision
- **PowerShell (Microsoft.Graph SDK)** for tenant configuration: users, groups, policies, roles, apps.
- **Python (azure-identity + Microsoft Graph REST)** for data processing and reporting: HR feed transformation, reports, analytics.
- **Az PowerShell** for Azure resources (Log Analytics, RBAC, managed identities).
- **Entra admin center** where no API exists, documented as a manual step with screenshots in `evidence/`.

## Consequences
Scripts are idempotent where practical (check, then create). Unattended automation uses certificate-based app credentials, never client secrets in files.
