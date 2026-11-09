#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Checks what the provisioning service did with an upload, and whether Entra ID now matches HR.

.DESCRIPTION
    An HTTP 202 from /bulkUpload only means "received". This script answers the real questions:
      1. What did the provisioning service do? (provisioning logs: create / update / disable / skip / fail)
      2. Does Entra ID match the HR snapshot? (every record present, enabled state correct,
         job code and manager populated)

    Exit code 1 if any record failed or any mismatch exists, so a scheduled run can alert on it.
.EXAMPLE
    ./04-Get-ProvisioningResults.ps1 -Since '2026-11-07T09:00:00Z' -AsOf 2026-11-07
#>
param(
    [Parameter(Mandatory)] [datetime] $Since,
    [datetime] $AsOf = (Get-Date).Date,
    [switch]   $Interactive
)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
if ($Interactive) { Connect-Danotech -Scopes 'AuditLog.Read.All', 'User.Read.All' } else { Connect-Danotech -AppOnly }
$target = Get-Content (Join-Path $phase 'config\provisioning-target.local.json') -Raw | ConvertFrom-Json

# 1. Provisioning logs for this app since the upload
$sinceIso = $Since.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$uri = "v1.0/auditLogs/provisioning?`$filter=activityDateTime ge $sinceIso&`$top=500"
$logs = @()
while ($uri) { $p = Invoke-MgGraphRequest -Method GET -Uri $uri; $logs += $p.value; $uri = $p.'@odata.nextLink' }
$logs = @($logs | Where-Object { $_.servicePrincipal.id -eq $target.servicePrincipalId })

Write-Host "`nProvisioning log entries since $sinceIso : $($logs.Count)" -ForegroundColor Cyan
$logs | Group-Object { $_.provisioningAction }, { $_.provisioningStatusInfo.status } |
    ForEach-Object { [pscustomobject]@{ Action = $_.Values[0]; Status = $_.Values[1]; Count = $_.Count } } |
    Sort-Object Action | Format-Table -AutoSize
$failed = @($logs | Where-Object { $_.provisioningStatusInfo.status -eq 'failure' })
foreach ($f in $failed) {
    Write-Host ("  FAILED {0}: {1}" -f $f.sourceIdentity.id, $f.provisioningStatusInfo.errorInformation.reason) -ForegroundColor Red
}
if ($logs.Count -eq 0) { Write-Host '  No entries yet. Processing takes 5-10 minutes; try again shortly.' -ForegroundColor Yellow }

# 2. Reconcile Entra ID against the HR snapshot
$snapshot = Join-Path $phase ("output\hr-snapshot-{0}.csv" -f $AsOf.ToString('yyyyMMdd'))
$hr = Import-Csv $snapshot -Encoding utf8
$uri = 'v1.0/users?$select=id,userPrincipalName,employeeId,accountEnabled,manager,onPremisesExtensionAttributes&$expand=manager($select=employeeId)&$top=999'
$users = @(); while ($uri) { $p = Invoke-MgGraphRequest -Method GET -Uri $uri; $users += $p.value; $uri = $p.'@odata.nextLink' }
$byEmp = @{}; foreach ($u in $users) { if ($u.employeeId -and -not $u.userPrincipalName.StartsWith('adm.')) { $byEmp[$u.employeeId] = $u } }

$mismatch = @()
foreach ($r in $hr) {
    $end = if ($r.EndDate) { [datetime]::ParseExact($r.EndDate, 'yyyy-MM-dd', $null) } else { $null }
    if ($r.EmploymentStatus -eq 'Terminated') { continue }           # skipped or disabled by design
    $u = $byEmp[$r.EmployeeId]
    if (-not $u) { $mismatch += "$($r.EmployeeId) $($r.DisplayName): no account"; continue }
    $shouldBeEnabled = ($r.EmploymentStatus -eq 'Active') -and (-not $end -or $end -ge $AsOf.Date)
    if ([bool]$u.accountEnabled -ne $shouldBeEnabled) { $mismatch += "$($r.EmployeeId) $($r.DisplayName): accountEnabled=$($u.accountEnabled), expected $shouldBeEnabled" }
    if ($u.onPremisesExtensionAttributes.extensionAttribute1 -ne $r.JobCode) { $mismatch += "$($r.EmployeeId) $($r.DisplayName): JobCode '$($u.onPremisesExtensionAttributes.extensionAttribute1)', expected $($r.JobCode)" }
    if ($r.ManagerEmployeeId -and $u.manager.employeeId -ne $r.ManagerEmployeeId) { $mismatch += "$($r.EmployeeId) $($r.DisplayName): manager not set to $($r.ManagerEmployeeId)" }
}

$expected = @($hr | Where-Object EmploymentStatus -ne 'Terminated').Count
Write-Host "Reconciliation: $($byEmp.Count) HR-linked accounts in Entra ID; $expected expected non-terminated records" -ForegroundColor Cyan
if ($mismatch) { $mismatch | Select-Object -First 25 | ForEach-Object { Write-Host "  MISMATCH $_" -ForegroundColor Yellow } }
else { Write-Host '  Entra ID matches HR: every record present, enabled state, job code and manager correct.' -ForegroundColor Green }

$stamp = $AsOf.ToString('yyyyMMdd')
[ordered]@{ since = $sinceIso; asOf = $AsOf.ToString('yyyy-MM-dd'); logEntries = $logs.Count; failures = $failed.Count
            hrLinkedAccounts = $byEmp.Count; expected = $expected; mismatches = $mismatch } |
    ConvertTo-Json -Depth 4 | Set-Content (Join-Path $phase "evidence\$stamp-provisioning-reconciliation.json") -Encoding utf8
if ($failed -or $mismatch) { exit 1 }
