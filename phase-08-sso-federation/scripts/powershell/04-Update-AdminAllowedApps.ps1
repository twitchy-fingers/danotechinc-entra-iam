#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Lets admin accounts reach the apps they administer just-in-time, and nothing else.

.DESCRIPTION
    Phase 07's CA103 blocks admin accounts from every app except admin tools. WordPress and the
    Keycloak broker are administered through PIM-managed groups by ADMIN accounts (policy AC-10),
    so those two apps must be allowed. This script:
      1. reads the apps marked adminViaPimGroup in federation-design.json
      2. adds their application IDs to phase-07\config\zero-trust-config.json (adminAllowedApps)
      3. redeploys CA103 from its definition (-UpdateExisting -Only CA103)
    Commit the changed Phase 07 config in the same pull request: the allow-list is reviewed code.
#>
$ErrorActionPreference = 'Stop'
$phase   = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$p07     = Resolve-Path (Join-Path $phase '..\phase-07-zero-trust-conditional-access')
$design  = Get-Content (Join-Path $phase 'config\federation-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
$cfgPath = Join-Path $p07 'config\zero-trust-config.json'
$cfg     = Get-Content $cfgPath -Raw | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Application.Read.All'

$changed = $false
foreach ($a in $design.apps | Where-Object adminViaPimGroup) {
    $sp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=displayName eq '$($a.displayName)'&`$select=appId").value | Select-Object -First 1
    if (-not $sp) { Write-Host "$($a.displayName) not found; create it first" -ForegroundColor Yellow; continue }
    if ($cfg.adminAllowedApps.appId -contains $sp.appId) { Write-Host "already allowed: $($a.displayName)"; continue }
    $cfg.adminAllowedApps += [pscustomobject]@{ name = $a.displayName; appId = $sp.appId; addedIn = '08' }
    Write-Host "allow-listed for admin accounts: $($a.displayName)" -ForegroundColor Green
    $changed = $true
}
if ($changed) {
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding utf8
    & (Join-Path $p07 'scripts\powershell\01-Deploy-ConditionalAccess.ps1') -UpdateExisting -Only CA103
}
