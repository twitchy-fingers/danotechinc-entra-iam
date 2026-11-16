#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    The Phase 07 control test: checks the whole Conditional Access estate and exports it as evidence.

.DESCRIPTION
      CA-01  Every policy excludes the break-glass group (and none includes it)
      CA-02  Baseline is enforced: CA000 (legacy auth) and CA001 (MFA, all users) enabled
      CA-03  Admin protection is enforced: CA100 (phishing-resistant) and CA102 (activation) enabled
      CA-04  No policy has sat in report-only for more than 14 days (decide: enforce or delete)
      CA-05  The admin onboarding exclusion group is empty (it's for hours, not days)
      CA-06  No policy excludes individual users (exceptions go through groups, so they're visible)
      CA-07  Every enabled workforce policy is at Ring 3 (everyone) by the end of the phase (-Final)
    Exit code 1 on any failure. Exports every policy to evidence\YYYYMMDD-ca-policies.json.
#>
param([switch] $Final)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$cfg   = Get-Content (Join-Path $phase 'config\zero-trust-config.json') -Raw | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Policy.Read.All', 'Group.Read.All'

$gid = { param($n) ((Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$n'&`$select=id").value | Select-Object -First 1).id }
$bg = & $gid $cfg.groups.breakGlass; $onb = & $gid $cfg.groups.adminOnboarding.name
$pol = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/policies').value
$f = [System.Collections.Generic.List[object]]::new(); $add = { param($c, $m) $f.Add([pscustomobject]@{ Check = $c; Finding = $m }) }
$byNum = { param($n) $pol | Where-Object { $_.displayName -like "$n-*" } | Select-Object -First 1 }

foreach ($p in $pol) {
    $u = $p.conditions.users
    if (@($u.excludeGroups) -notcontains $bg) { & $add 'CA-01' "$($p.displayName) doesn't exclude break-glass" }
    if (@($u.includeGroups) -contains $bg)   { & $add 'CA-01' "$($p.displayName) INCLUDES break-glass" }
    if (@($u.excludeUsers | Where-Object { $_ -and $_ -ne 'GuestsOrExternalUsers' }).Count) { & $add 'CA-06' "$($p.displayName) excludes individual users" }
    if ($p.state -eq 'enabledForReportingButNotEnforced') {
        $since = [datetime]($p.modifiedDateTime ?? $p.createdDateTime)
        if (((Get-Date) - $since).TotalDays -gt 14) { & $add 'CA-04' "$($p.displayName) report-only since $($since.ToString('yyyy-MM-dd'))" }
    }
}
foreach ($n in 'CA000', 'CA001', 'CA100', 'CA102') {
    $p = & $byNum $n
    $check = if ($n -in 'CA000', 'CA001') { 'CA-02' } else { 'CA-03' }
    if (-not $p) { & $add $check "$n missing" } elseif ($p.state -ne 'enabled') { & $add $check "$($p.displayName) is $($p.state)" }
}
if ($onb) { $m = @((Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$onb/members?`$select=userPrincipalName").value); if ($m) { & $add 'CA-05' "Admin onboarding exclusion not empty: $($m.userPrincipalName -join ', ')" } }
if ($Final) {
    foreach ($n in $cfg.rollout.ringManagedPolicies) {
        $p = & $byNum $n
        if (-not $p -or $p.state -ne 'enabled' -or @($p.conditions.users.includeUsers) -notcontains 'All') { & $add 'CA-07' "$n isn't enforced for everyone" }
    }
}
$stamp = Get-Date -Format 'yyyyMMdd'
$pol | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $phase "evidence\$stamp-ca-policies.json") -Encoding utf8
$pol | Sort-Object displayName | ForEach-Object { [pscustomobject]@{ Policy = $_.displayName; State = $_.state } } | Format-Table -AutoSize
if ($f.Count) { $f | Format-Table -AutoSize -Wrap; exit 1 }
Write-Host 'PASS: every policy excludes break-glass; baseline and admin protection enforced; no stale report-only policies.' -ForegroundColor Green
