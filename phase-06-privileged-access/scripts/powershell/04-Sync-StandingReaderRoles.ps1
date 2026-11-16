#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Keeps the standing read-only directory roles in step with the dynamic job-role groups.

.DESCRIPTION
    The Phase 03 model gives three job roles a standing, READ-ONLY directory role on their daily
    account (High sensitivity, not Privileged, so no PIM):
        JR-IT-IAM, JR-SEC-GRC -> Global Reader       JR-SEC-SOC -> Security Reader
    Entra ID can't assign a directory role to a DYNAMIC group, so this script reconciles instead:
      - every current member of the source groups gets the role (active, permanent)
      - anyone holding the role who is no longer in a source group LOSES it (movers, leavers)
    Admin and break-glass accounts are never touched. Run after each Phase 04 feed, or daily.
.EXAMPLE
    ./04-Sync-StandingReaderRoles.ps1 -WhatIf
#>
param([switch] $WhatIf)
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\privileged-access-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'RoleManagement.ReadWrite.Directory', 'Group.Read.All', 'User.Read.All'

foreach ($r in $design.standingReaderRoles) {
    Write-Host "`n$($r.role) (from $($r.fromGroups -join ', '))" -ForegroundColor Cyan
    $should = @{}
    foreach ($gn in $r.fromGroups) {
        $g = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$gn'&`$select=id").value | Select-Object -First 1
        if (-not $g) { throw "$gn not found (Phase 05)." }
        $uri = "v1.0/groups/$($g.id)/members/microsoft.graph.user?`$select=id,userPrincipalName,employeeType&`$top=999"
        while ($uri) { $p = Invoke-MgGraphRequest -Method GET -Uri $uri; foreach ($m in $p.value) { if ($m.employeeType -ne 'AdminAccount') { $should[$m.id] = $m.userPrincipalName } }; $uri = $p.'@odata.nextLink' }
    }
    $current = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$($r.roleTemplateId)'&`$expand=principal").value |
        Where-Object { $_.directoryScopeId -eq '/' -and $_.principal.'@odata.type' -eq '#microsoft.graph.user' }
    $have = @{}; foreach ($c in $current) { $have[$c.principalId] = $c }

    foreach ($id in $should.Keys) {
        if ($have.ContainsKey($id)) { Write-Host "  keep    $($should[$id])"; continue }
        if (-not $WhatIf) { Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignments' -Body @{ principalId = $id; roleDefinitionId = $r.roleTemplateId; directoryScopeId = '/' } | Out-Null }
        Write-Host "  add     $($should[$id])" -ForegroundColor Green
    }
    foreach ($c in $current) {
        if ($should.ContainsKey($c.principalId)) { continue }
        if ($c.principal.employeeType -eq 'AdminAccount' -or $c.principal.userPrincipalName -like 'bg-*') { continue }
        if (-not $WhatIf) { Invoke-MgGraphRequest -Method DELETE -Uri "v1.0/roleManagement/directory/roleAssignments/$($c.id)" }
        Write-Host "  remove  $($c.principal.userPrincipalName) (no longer in a source group)" -ForegroundColor Yellow
    }
}
if ($WhatIf) { Write-Host "`nWhatIf: nothing changed." -ForegroundColor Yellow }
