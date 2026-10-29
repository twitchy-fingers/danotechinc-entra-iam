#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Applies DanotechInc's baseline tenant hardening settings.

.DESCRIPTION
    Changes the default permissions every member and guest gets, and turns on
    the admin consent workflow so users can request apps instead of consenting
    to them directly. Exports before/after JSON as evidence.

    Run as adm.daniel.opara.

.PARAMETER ConsentReviewerUpn
    Who reviews app consent requests. Phase 06 replaces this with the IAM admin group.
#>
param(
    [string] $ConsentReviewerUpn = 'adm.daniel.opara@danotechinc.onmicrosoft.com',
    [string] $EvidenceFolder = (Join-Path $PSScriptRoot '..\..\evidence')
)

. (Join-Path $PSScriptRoot '..\..\..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Policy.ReadWrite.Authorization', 'Policy.ReadWrite.ConsentRequest', 'User.Read.All'

$stamp = Get-Date -Format 'yyyyMMdd'
$before = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/policies/authorizationPolicy'
$before | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $EvidenceFolder "$stamp-authorization-policy-before.json")

# Restricted Guest User role: guests see only their own directory object.
$restrictedGuestRoleId = '2af84b1e-32c8-42b7-82bc-daa82404023b'

$body = @{
    allowInvitesFrom                          = 'adminsAndGuestInviters'  # guests go through entitlement management (Phase 12)
    allowedToSignUpEmailBasedSubscriptions    = $false                     # no self-service "viral" sign-ups
    allowEmailVerifiedUsersToJoinOrganization = $false
    guestUserRoleId                           = $restrictedGuestRoleId
    defaultUserRolePermissions = @{
        allowedToCreateApps           = $false   # app registrations are identities with credentials
        allowedToCreateSecurityGroups = $false   # groups grant access; ad-hoc groups = ungoverned access
        allowedToCreateTenants        = $false   # no shadow tenants
        allowedToReadOtherUsers       = $true    # leave on: apps and people search depend on it
        permissionGrantPoliciesAssigned = @()    # empty = users cannot consent to apps
    }
}
Invoke-MgGraphRequest -Method PATCH -Uri 'v1.0/policies/authorizationPolicy' -Body $body
Write-Host 'Authorization policy updated' -ForegroundColor Green

# Admin consent workflow: with user consent off, this is how people ask for an app.
$reviewer = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($ConsentReviewerUpn)?`$select=id"
Invoke-MgGraphRequest -Method PUT -Uri 'v1.0/policies/adminConsentRequestPolicy' -Body @{
    isEnabled             = $true
    notifyReviewers       = $true
    remindersEnabled      = $true
    requestDurationInDays = 14
    reviewers             = @(@{ query = "/users/$($reviewer.id)"; queryType = 'MicrosoftGraph' })
}
Write-Host "Admin consent workflow enabled (reviewer: $ConsentReviewerUpn)" -ForegroundColor Green

$after = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/policies/authorizationPolicy'
$after | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $EvidenceFolder "$stamp-authorization-policy-after.json")

Write-Host "`nSettings with no Graph API - set these in the Entra admin center (walkthrough Step 6b):" -ForegroundColor Yellow
@(
    'Users > User settings > Restrict access to Microsoft Entra admin center = Yes',
    'Users > User settings > LinkedIn account connections = No',
    'Groups > General > Users can create Microsoft 365 groups in Azure portals, API or PowerShell = No',
    'Groups > General > Owners can manage group membership requests in My Groups = No'
) | ForEach-Object { Write-Host "  - $_" }
