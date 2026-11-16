#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Moves the workforce policies (CA002, CA004, CA200, CA201) through the rollout rings.

.DESCRIPTION
    A new policy is never switched on for 200 people at once. It goes:
        report-only -> Ring 0 (IAM team, 4) -> Ring 1 (+ IT and Security, 26)
                    -> Ring 2 (+ licensed cohort, all departments) -> Ring 3 (everyone)
    Each ring sets the policy's included groups and turns enforcement ON (unless -ReportOnly).
    Break-glass stays excluded in every ring: the script refuses to remove that exclusion.
    The charter (section 13) asks for each ring to be stable before moving on; the script asks you
    to confirm you checked the report-only results and the previous ring's sign-ins.
.EXAMPLE
    ./02-Set-CaRolloutRing.ps1 -Ring 0
    ./02-Set-CaRolloutRing.ps1 -Ring 1 -Policy CA002, CA004
    ./02-Set-CaRolloutRing.ps1 -Ring 3
#>
param(
    [Parameter(Mandatory)] [ValidateSet(0, 1, 2, 3)] [int] $Ring,
    [string[]] $Policy,
    [switch] $ReportOnly,
    [switch] $Force
)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$cfg   = Get-Content (Join-Path $phase 'config\zero-trust-config.json') -Raw | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'Group.Read.All'

$targets = if ($Policy) { $Policy } else { $cfg.rollout.ringManagedPolicies }
$ringDef = $cfg.rollout.rings."$Ring"
$bg = ((Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($cfg.groups.breakGlass)'&`$select=id").value)[0].id

$users = @{ excludeGroups = @($bg) }
if ($ringDef.includeUsers) { $users.includeUsers = @('All'); $users.includeGroups = @() }
else {
    $users.includeUsers = @()
    $users.includeGroups = @(foreach ($n in $ringDef.includeGroups) {
        $id = ((Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$n'&`$select=id").value | Select-Object -First 1).id
        if (-not $id) { throw "Ring group $n not found." }; $id })
}
$state = if ($ReportOnly) { 'enabledForReportingButNotEnforced' } else { 'enabled' }

Write-Host "Ring $Ring ($($ringDef.who)) -> $state for $($targets -join ', ')" -ForegroundColor Cyan
if (-not $Force -and -not $ReportOnly) {
    $ok = Read-Host 'Have you reviewed the report-only results (kql\report-only-impact.kql) and the previous ring''s sign-ins? (yes/no)'
    if ($ok -ne 'yes') { Write-Host 'Stopped. Nothing changed.' -ForegroundColor Yellow; return }
}

$live = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/policies').value
foreach ($t in $targets) {
    $p = $live | Where-Object { $_.displayName -like "$t-*" } | Select-Object -First 1
    if (-not $p) { Write-Host "  $t not found; deploy it first (script 01)." -ForegroundColor Red; continue }
    $u = @{ includeUsers = $users.includeUsers; includeGroups = $users.includeGroups
            excludeGroups = @(@($p.conditions.users.excludeGroups) + $bg | Where-Object { $_ } | Sort-Object -Unique)
            excludeUsers = @($p.conditions.users.excludeUsers | Where-Object { $_ }) }
    Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/identity/conditionalAccess/policies/$($p.id)" -Body (@{ state = $state; conditions = @{ users = $u } } | ConvertTo-Json -Depth 10) -ContentType 'application/json' | Out-Null
    Write-Host "  $($p.displayName): ring $Ring, $state" -ForegroundColor Green
}
$log = Join-Path $phase 'evidence\rollout-log.csv'
$targets | ForEach-Object { [pscustomobject]@{ Time = (Get-Date).ToUniversalTime().ToString('o'); Policy = $_; Ring = $Ring; State = $state; By = (Get-MgContext).Account } } |
    Export-Csv $log -Append -NoTypeInformation -Encoding utf8
Write-Host "Logged to evidence\rollout-log.csv" -ForegroundColor Cyan
