#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Creates the three pilot groups and gives pilot members a lab mail address.

.DESCRIPTION
    Pilot groups (assigned, with a named owner) stand in for the production role groups where an
    external platform limits how many users the lab can have (Salesforce Developer Edition licences,
    personal GitHub accounts, a partner's Okta org).

    GitHub's SCIM sends an invitation EMAIL, and Okta keys users on the email claim, so every pilot
    member needs a `mail` value. Managers already have one (Phase 04 Step 8); this sets the same kind
    of plus-address (you+first.last@...) for the others. The HR feed doesn't map `mail`, so it's kept.
.EXAMPLE
    ./01-New-PilotGroups.ps1 -Inbox you@outlook.com
#>
param([Parameter(Mandatory)] [ValidatePattern('^[^@+\s]+@[^@\s]+\.[^@\s]+$')] [string] $Inbox)
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\federation-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Group.ReadWrite.All', 'User.ReadWrite.All'
$local, $domain = $Inbox.Split('@')

foreach ($pg in $design.pilotGroups) {
    $g = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($pg.name)'&`$select=id").value | Select-Object -First 1
    if (-not $g) {
        $g = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/groups' -Body @{ displayName = $pg.name; mailEnabled = $false; securityEnabled = $true
            mailNickname = $pg.name.ToLower(); description = "$($pg.description) Owner: $($pg.owner)." }
        Write-Host "Created $($pg.name)" -ForegroundColor Green; Start-Sleep -Seconds 10
        $owner = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users?`$filter=displayName eq '$($pg.owner)'&`$select=id").value | Select-Object -First 1
        if ($owner) { Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($g.id)/owners/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($owner.id)" } }
    }
    $current = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$($g.id)/members?`$select=userPrincipalName").value.userPrincipalName
    foreach ($upn in $pg.members) {
        $u = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($upn)?`$select=id,mail,accountEnabled"
        if (-not $u.accountEnabled) { Write-Host "  $upn is disabled; not added" -ForegroundColor Yellow; continue }
        if ($current -notcontains $upn) {
            Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($g.id)/members/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($u.id)" }
            Write-Host "  + $upn" -ForegroundColor Green
        }
        if (-not $u.mail) {
            $addr = "$local+$($upn.Split('@')[0])@$domain"
            Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/users/$($u.id)" -Body @{ mail = $addr }
            Write-Host "    mail -> $addr"
        }
    }
}
