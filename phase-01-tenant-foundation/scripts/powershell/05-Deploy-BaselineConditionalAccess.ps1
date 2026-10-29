#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Replaces security defaults with DanotechInc's baseline Conditional Access policies.

.DESCRIPTION
    Security defaults and Conditional Access can't run together, and security
    defaults can't exclude break-glass accounts. This script:

      1. Verifies the break-glass exclusion group exists and has 2 members
         (lockout guard: never deploy CA without a working way back in).
      2. Disables security defaults.
      3. Immediately creates CA000, CA001 and CA100 in the ENABLED state.

    Why enabled rather than report-only? The tenant already has these exact
    controls via security defaults. Report-only would mean a window with
    *less* protection than today. New policies in Phase 07 go through
    report-only first because they introduce new behaviour.

    Run as adm.daniel.opara, with MFA already registered.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $PolicyFolder   = (Join-Path $PSScriptRoot '..\..\policies\conditional-access'),
    [string] $EvidenceFolder = (Join-Path $PSScriptRoot '..\..\evidence')
)

. (Join-Path $PSScriptRoot '..\..\..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'Policy.ReadWrite.SecurityDefaults', 'Application.Read.All', 'Group.Read.All'

# --- Lockout guard ---------------------------------------------------------
$grp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq 'GRP-CA-Exclude-BreakGlass'").value
if (-not $grp) { throw 'Break-glass exclusion group not found. Run 02-New-BreakGlassAccounts.ps1 first.' }
$members = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$($grp[0].id)/members?`$select=id").value
if (@($members).Count -lt 2) { throw "Exclusion group has $(@($members).Count) member(s); expected 2. Aborting to prevent lockout." }
$bgGroupId = $grp[0].id
Write-Host "Lockout guard passed: $(@($members).Count) break-glass accounts excluded" -ForegroundColor Green

# --- Security defaults -----------------------------------------------------
$sd = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
if ($sd.isEnabled) {
    if ($PSCmdlet.ShouldProcess('Security defaults', 'Disable and replace with Conditional Access')) {
        Invoke-MgGraphRequest -Method PATCH -Uri 'v1.0/policies/identitySecurityDefaultsEnforcementPolicy' -Body @{ isEnabled = $false }
        Write-Host 'Security defaults disabled' -ForegroundColor Yellow
    } else { return }
}

# --- Policies --------------------------------------------------------------
$existing = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/policies?$select=id,displayName').value
foreach ($file in Get-ChildItem $PolicyFolder -Filter 'CA*.json' | Sort-Object Name) {
    $json = (Get-Content $file.FullName -Raw) -replace '\{\{BREAKGLASS_GROUP_ID\}\}', $bgGroupId
    $policy = $json | ConvertFrom-Json -AsHashtable
    if (($existing | ForEach-Object { $_.displayName }) -contains $policy.displayName) {
        Write-Host "Exists, skipped: $($policy.displayName)" -ForegroundColor Yellow
        continue
    }
    Invoke-MgGraphRequest -Method POST -Uri 'v1.0/identity/conditionalAccess/policies' -Body $policy | Out-Null
    Write-Host "Created: $($policy.displayName) [$($policy.state)]" -ForegroundColor Green
}

$stamp = Get-Date -Format 'yyyyMMdd'
Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/policies' |
    ConvertTo-Json -Depth 20 | Set-Content (Join-Path $EvidenceFolder "$stamp-ca-policies.json")
Write-Host "Evidence written. Now test sign-in in a private browser window (walkthrough Step 7)." -ForegroundColor Cyan
