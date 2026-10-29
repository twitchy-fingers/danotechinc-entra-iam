#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Removes Global Administrator from Daniel Opara's daily account, safely.

.DESCRIPTION
    The lockout guard refuses to run unless at least 3 OTHER accounts hold
    Global Administrator (2 break-glass + the adm. account), and unless you
    are signed in as one of them, not as the account being changed.

    It also stamps employeeId DT01001 on the daily account. When the HR feed
    goes live in Phase 04, inbound provisioning matches on employeeId, so it
    adopts Daniel's existing account instead of creating a duplicate.

    Run as adm.daniel.opara.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $DailyUpn   = 'daniel.opara@danotechinc.onmicrosoft.com',
    [string] $EmployeeId = 'DT01001'
)

. (Join-Path $PSScriptRoot '..\..\..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'User.ReadWrite.All', 'RoleManagement.ReadWrite.Directory'

$ga = '62e90394-69f5-4237-9190-012177145e10'
$me = (Get-MgContext).Account
if ($me -ieq $DailyUpn) { throw "You're signed in as $DailyUpn. Sign in as adm.daniel.opara instead." }

$daily = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($DailyUpn)?`$select=id,employeeId"
$holders = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$ga'&`$expand=principal").value
$others  = $holders | Where-Object { $_.principalId -ne $daily.id }

Write-Host 'Current Global Administrators:' -ForegroundColor Cyan
$holders | ForEach-Object { "  - $($_.principal.userPrincipalName)" }

if (@($others).Count -lt 3) {
    throw "Only $(@($others).Count) other Global Admin(s). Need 2 break-glass + 1 admin account before removing this one."
}

$target = $holders | Where-Object { $_.principalId -eq $daily.id }
if ($target -and $PSCmdlet.ShouldProcess($DailyUpn, 'Remove Global Administrator')) {
    Invoke-MgGraphRequest -Method DELETE -Uri "v1.0/roleManagement/directory/roleAssignments/$($target.id)"
    Write-Host "Removed Global Administrator from $DailyUpn" -ForegroundColor Green
}
elseif (-not $target) { Write-Host "$DailyUpn holds no Global Admin assignment" -ForegroundColor Yellow }

if ($daily.employeeId -ne $EmployeeId) {
    Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/users/$($daily.id)" -Body @{ employeeId = $EmployeeId }
    Write-Host "Set employeeId=$EmployeeId on $DailyUpn (HR feed will match this account in Phase 04)" -ForegroundColor Green
}
