#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Exports Phase 05 configuration as audit evidence: groups and rules, app roles, role-to-group
    assignments, licensing group state, and the app's sign-in history.
#>
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Group.Read.All', 'Application.Read.All', 'AuditLog.Read.All'
$cfg = Get-Content (Join-Path $phase 'config\expenses-app.local.json') -Raw | ConvertFrom-Json
$stamp = Get-Date -Format 'yyyyMMdd'

$groups = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=startswith(displayName,'GRP-')&`$select=id,displayName,membershipRule,groupTypes&`$top=999").value
$groupRows = foreach ($g in $groups) {
    $count = Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$($g.id)/members/`$count" -Headers @{ ConsistencyLevel = 'eventual' } -OutputType PSObject
    [pscustomobject]@{ Group = $g.displayName; Type = $(if ($g.groupTypes -contains 'DynamicMembership') { 'Dynamic' } else { 'Assigned' }); Members = $count; Rule = $g.membershipRule }
}
$groupRows | Sort-Object Group | Export-Csv (Join-Path $phase "evidence\$stamp-groups.csv") -NoTypeInformation -Encoding utf8

$assign = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($cfg.servicePrincipalId)/appRoleAssignedTo?`$top=999").value
$app = Invoke-MgGraphRequest -Method GET -Uri "v1.0/applications/$($cfg.applicationObjectId)?`$select=appRoles,web,passwordCredentials"
$roleName = @{}; foreach ($r in $app.appRoles) { $roleName[$r.id] = $r.value }
$assign | ForEach-Object { [pscustomobject]@{ Group = $_.principalDisplayName; AppRole = $roleName[$_.appRoleId] } } |
    Sort-Object AppRole, Group | Export-Csv (Join-Path $phase "evidence\$stamp-app-role-assignments.csv") -NoTypeInformation -Encoding utf8

$signins = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/auditLogs/signIns?`$filter=appId eq '$($cfg.appId)'&`$top=200").value |
    ForEach-Object { [pscustomobject]@{ Time = $_.createdDateTime; User = $_.userPrincipalName; Result = $_.status.errorCode; Reason = $_.status.failureReason; CA = $_.conditionalAccessStatus } }
$signins | Export-Csv (Join-Path $phase "evidence\$stamp-expenses-signins.csv") -NoTypeInformation -Encoding utf8

[ordered]@{ redirectUris = $app.web.redirectUris; secretExpiries = @($app.passwordCredentials.endDateTime) } |
    ConvertTo-Json | Set-Content (Join-Path $phase "evidence\$stamp-expenses-app-config.json") -Encoding utf8
Write-Host "Evidence written to $(Join-Path $phase 'evidence')" -ForegroundColor Green
$groupRows | Sort-Object Group | Format-Table Group, Members -AutoSize
