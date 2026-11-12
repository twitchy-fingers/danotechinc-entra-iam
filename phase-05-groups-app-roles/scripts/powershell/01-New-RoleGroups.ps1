#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Creates the dynamic role groups from the Phase 03 model, and checks any you built in the portal.

.DESCRIPTION
    Reads phase-03-rbac-design\generated\dynamic-group-rules.json, which the Phase 03 simulation
    generated from the same data it tested. So the rules in Entra ID are exactly the rules that
    were simulated against all 200 people.

    You build the first group (GRP-DYN-ALL-Workforce) by hand in the portal (walkthrough Step 1).
    This script creates the other 40, and for any group that already exists it compares the live
    rule with the model. A typo in the portal shows up as drift and is corrected.

    For each Birthright, Department and Job role:
      - creates a security group with dynamic membership and the generated rule
      - sets the role owner as group owner (accountability for Phase 13 reviews)
      - if the group already exists but its rule differs from the model, CORRECTS it (drift repair)

    Privileged roles (Phase 06) and requestable roles (Phase 12) are skipped here.
    Run as adm.daniel.opara.
#>
param([switch] $WhatIf)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$rulesFile = Join-Path $phase '..\phase-03-rbac-design\generated\dynamic-group-rules.json'
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Group.ReadWrite.All', 'User.Read.All'

$roles = Get-Content $rulesFile -Raw -Encoding utf8 | ConvertFrom-Json | Where-Object membershipType -eq 'Dynamic'
Write-Host "$($roles.Count) dynamic roles in the Phase 03 model" -ForegroundColor Cyan

$summary = @()
foreach ($r in $roles) {
    $existing = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($r.groupName)'&`$select=id,membershipRule").value | Select-Object -First 1
    $desc = "Role $($r.roleId) ($($r.layer)): $($r.description). Owner: $($r.owner). Managed as code from the Phase 03 role model; change model\roles.csv, not this rule."
    if ($desc.Length -gt 1000) { $desc = $desc.Substring(0, 1000) }

    if ($existing) {
        if ($existing.membershipRule -ne $r.membershipRule) {
            if (-not $WhatIf) { Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/groups/$($existing.id)" -Body @{ membershipRule = $r.membershipRule } }
            $summary += [pscustomobject]@{ Group = $r.groupName; Action = 'Rule corrected (drift)'; Expected = $r.expectedMembers }
        } else {
            $summary += [pscustomobject]@{ Group = $r.groupName; Action = 'Exists, matches model'; Expected = $r.expectedMembers }
        }
        continue
    }
    if ($WhatIf) { $summary += [pscustomobject]@{ Group = $r.groupName; Action = 'Would create'; Expected = $r.expectedMembers }; continue }

    $nick = ($r.groupName -replace '[^A-Za-z0-9-]', '').ToLower()
    $g = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/groups' -Body @{
        displayName                   = $r.groupName
        description                   = $desc
        mailEnabled                   = $false
        mailNickname                  = $nick
        securityEnabled               = $true
        groupTypes                    = @('DynamicMembership')
        membershipRule                = $r.membershipRule
        membershipRuleProcessingState = 'On'
    }
    # Owner = the role owner from the model (looked up by display name)
    $owner = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users?`$filter=displayName eq '$($r.owner -replace "'", "''")' and employeeType ne 'AdminAccount'&`$select=id&`$count=true" -Headers @{ ConsistencyLevel = 'eventual' }).value | Select-Object -First 1
    if ($owner) {
        Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($g.id)/owners/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($owner.id)" }
    }
    $summary += [pscustomobject]@{ Group = $r.groupName; Action = 'Created'; Expected = $r.expectedMembers }
}
$summary | Format-Table -AutoSize
Write-Host 'Dynamic membership is evaluated in the background: allow 15-60 minutes before running 02-Test-GroupMembership.ps1.' -ForegroundColor Cyan
