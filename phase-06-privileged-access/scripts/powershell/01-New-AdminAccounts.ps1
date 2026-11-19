#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Creates the dedicated admin accounts from the design, checks the ones built by hand,
    and creates the group Conditional Access uses to find every admin account.

.DESCRIPTION
    adm.adaeze.nwosu is built by hand in the portal (walkthrough Step 2) and adm.daniel.opara
    already exists from Phase 01. This script creates the other 12, and CHECKS every existing
    admin account against the design:
        displayName "ADM - <name>"; employeeId = the person's HR ID; employeeType = AdminAccount;
        usageLocation set; companyName EMPTY (keeps it out of HR workflows and workforce groups).

    New accounts get a 64-character random password that is never shown or stored. Admins
    never learn a password: they register a passkey with a one-time Temporary Access Pass
    (walkthrough Step 4). An account nobody knows the password for can't be password-sprayed.

    Also:
      - GRP-DYN-ALL-AdminAccounts: dynamic group of every admin account (Phase 07 targets it)
      - adds the two remaining licensed admin accounts to GRP-LIC-EntraSuite (ADR-0006)
    Run as adm.daniel.opara (with Global Administrator activated, or before Step 6 removes it).
#>
param([switch] $WhatIf)
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\privileged-access-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All'

function New-RandomPassword {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*-_=+'
    -join (1..64 | ForEach-Object { $chars[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)] })
}

$rows = @()
foreach ($a in $design.admins) {
    $u = $null
    try { $u = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($a.adminUpn)?`$select=id,displayName,employeeId,employeeType,usageLocation,companyName,accountEnabled, onPremisesExtensionAttributes" } catch {}
    if (-not $u) {
        if ($WhatIf) { $rows += [pscustomobject]@{ Account = $a.adminUpn; Tier = $a.tier; Result = 'Would create' }; continue }
        $nick = $a.adminUpn.Split('@')[0]
        Invoke-MgGraphRequest -Method POST -Uri 'v1.0/users' -Body @{
            accountEnabled = $true; displayName = $a.displayName; userPrincipalName = $a.adminUpn; mailNickname = $nick
            employeeId = $a.employeeId; employeeType = 'AdminAccount'; usageLocation = $a.usageLocation
            onPremisesExtensionAttributes = @{ extensionAttribute5 = 'AdminAccount' }
            jobTitle = "Privileged administrator account ($($a.tier))"
            passwordProfile = @{ password = (New-RandomPassword); forceChangePasswordNextSignIn = $false }
        } | Out-Null
        $rows += [pscustomobject]@{ Account = $a.adminUpn; Tier = $a.tier; Result = 'Created' }
        continue
    }
    $issues = @()
    if ($u.displayName -ne $a.displayName) { $issues += "displayName '$($u.displayName)'" }
    if ($u.employeeId -ne $a.employeeId)   { $issues += "employeeId '$($u.employeeId)', expected $($a.employeeId)" }
    if ($u.onPremisesExtensionAttributes.extensionAttribute5 -ne 'AdminAccount') { $issues += "extensionAttribute5 '$($u.onPremisesExtensionAttributes.extensionAttribute5)', expected AdminAccount" }
    if ($u.employeeType -ne 'AdminAccount') { $issues += "employeeType '$($u.employeeType)', expected AdminAccount" }
    if (-not $u.usageLocation)             { $issues += 'usageLocation empty' }
    if ($u.companyName)                    { $issues += "companyName '$($u.companyName)' must be empty" }
    $rows += [pscustomobject]@{ Account = $a.adminUpn; Tier = $a.tier; Result = if ($issues) { 'DIFFERS: ' + ($issues -join '; ') } else { 'Exists, matches design' } }
}
$rows | Format-Table -AutoSize -Wrap

if (-not $WhatIf) {
    # Group of every admin account, for Conditional Access (Phase 07)
    $g = $design.adminAccountsGroup
    $existing = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($g.name)'").value | Select-Object -First 1
    if (-not $existing) {
        Invoke-MgGraphRequest -Method POST -Uri 'v1.0/groups' -Body @{
            displayName = $g.name; mailEnabled = $false; securityEnabled = $true; mailNickname = $g.name.ToLower()
            description = 'Every dedicated admin account (extensionAttribute5 = AdminAccount). Targeted by Phase 07 admin Conditional Access. Owner: IAM Manager.'
            groupTypes = @('DynamicMembership'); membershipRule = $g.rule; membershipRuleProcessingState = 'On' } | Out-Null
        Write-Host "Created $($g.name)" -ForegroundColor Green
    }

    # Licensed admin accounts (ADR-0006)
    $lic = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq 'GRP-LIC-EntraSuite'").value | Select-Object -First 1
    if ($lic) {
        $members = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$($lic.id)/members?`$select=userPrincipalName&`$top=999").value.userPrincipalName
        foreach ($upn in $design.licensedAdminAccounts) {
            if ($members -contains $upn) { continue }
            $id = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($upn)?`$select=id").id
            Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($lic.id)/members/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$id" }
            Write-Host "Added $upn to GRP-LIC-EntraSuite" -ForegroundColor Green
        }
    } else { Write-Host 'GRP-LIC-EntraSuite not found (Phase 05 Step 4); skipped.' -ForegroundColor Yellow }
}
if ($rows | Where-Object Result -like 'DIFFERS*') { Write-Host 'Fix the accounts marked DIFFERS in the portal (user > Properties) and rerun.' -ForegroundColor Yellow; exit 1 }
