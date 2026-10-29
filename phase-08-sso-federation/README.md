# Phase 08: SSO and Federation

> **Status: Planned.** This README outlines the scenario and scope. The full architecture, diagrams and `WALKTHROUGH.md` are added when the phase is built.

## Scenario

Fernanda Castillo (Sales Ops) wants Salesforce access to follow the HR record; Ngozi Balogun (Digital Marketing) needs WordPress logins without local passwords; Carlos Gutiérrez (DevOps) needs GitHub tied to company identity; and a partner-facing app uses Keycloak. DanotechInc also federates with a partner running Okta.

## Planned scope

- SAML 2.0 SSO + SCIM provisioning: Salesforce, Atlassian Cloud
- OIDC SSO: WordPress and the Phase 05 test app
- OAuth 2.0 flows: authorization code + PKCE, client credentials, on-behalf-of
- Identity brokering: Keycloak brokering to Entra ID; Entra ID ↔ Okta federation
- GitHub SSO

## Depends on

Phase 07.

**Previous:** [Phase 07](../phase-07-zero-trust-conditional-access/) · **Next:** [Phase 09](../phase-09-cloud-iam/)
