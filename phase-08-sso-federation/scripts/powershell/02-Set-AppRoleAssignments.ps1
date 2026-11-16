#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Assigns each federated app's roles to groups as designed, and reports anything extra.

.DESCRIPTION
    For every app in config\federation-design.json with lab assignments, the first assignment is
    made by hand in the portal (walkthrough). This script makes the rest, and for every app:
      - checks "Assignment required" is on (people without a role can't get a token at all)
      - assigns any missing group -> app role pair (app roles are matched by VALUE, or by display
        name for gallery apps whose roles are imported, like Salesforce profiles)
      - reports assignments that aren't in the design
.EXAMPLE
    ./02-Set-AppRoleAssignments.ps1 -App wordpress, keycloak
#>
param([string[]] $App)
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\federation-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Application.Read.All', 'AppRoleAssignment.ReadWrite.All', 'Group.Read.All'

foreach ($a in $design.apps | Where-Object { $_.labAssignments -and (-not $App -or $App -contains $_.key) }) {
    Write-Host "`n$($a.displayName)" -ForegroundColor Cyan
    $sp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=displayName eq '$($a.displayName)'").value | Select-Object -First 1
    if (-not $sp) { Write-Host '  not created yet; skipped' -ForegroundColor Yellow; continue }
    if (-not $sp.appRoleAssignmentRequired) { Write-Host '  WARNING: Assignment required is OFF: anyone in the tenant can sign in' -ForegroundColor Red }
    $assigned = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo?`$top=999").value
    $roleName = @{}; foreach ($r in $sp.appRoles) { $roleName[$r.id] = $r.value ?? $r.displayName }
    $wanted = @()
    foreach ($x in $a.labAssignments) {
        $role = $sp.appRoles | Where-Object { $_.value -eq $x.appRole -or $_.displayName -eq $x.appRole } | Select-Object -First 1
        if (-not $role) { Write-Host "  role '$($x.appRole)' not found on the app (for gallery apps: connect provisioning first so roles import)" -ForegroundColor Yellow; continue }
        $grp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($x.group)'&`$select=id").value | Select-Object -First 1
        if (-not $grp) { Write-Host "  group $($x.group) not found" -ForegroundColor Yellow; continue }
        $wanted += "$($grp.id)|$($role.id)"
        if ($assigned | Where-Object { $_.principalId -eq $grp.id -and $_.appRoleId -eq $role.id }) { Write-Host "  exists $($x.group) -> $($x.appRole)"; continue }
        Invoke-MgGraphRequest -Method POST -Uri "v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo" -Body @{ principalId = $grp.id; resourceId = $sp.id; appRoleId = $role.id } | Out-Null
        Write-Host "  added  $($x.group) -> $($x.appRole)" -ForegroundColor Green
    }
    foreach ($z in $assigned) {
        if ($wanted -notcontains "$($z.principalId)|$($z.appRoleId)") {
            Write-Host "  NOT IN DESIGN: $($z.principalDisplayName) -> $($roleName[$z.appRoleId])" -ForegroundColor Yellow
        }
    }
}
