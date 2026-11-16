#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Makes Tier 0 PIM activation require authentication context c1 (phishing-resistant, every time).

.DESCRIPTION
    Phase 06 required "MFA" to activate Global Administrator and Privileged Role Administrator.
    Any MFA, including an Authenticator push approved by a tired user or a session token stolen by
    a phishing proxy. With an authentication context, PIM asks Conditional Access (policy CA102)
    for a FRESH, phishing-resistant passkey sign-in at the moment of activation.

    For each Tier 0 role: removes plain MFA from the activation requirements (PIM doesn't allow
    both), enables authentication context c1, then re-checks the whole Tier 0 profile.
    Run as adm.adaeze.nwosu with Privileged Role Administrator activated, AFTER CA102 is enabled.
#>
param([string] $ContextId = 'c1')
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$p06    = Join-Path $phase '..\phase-06-privileged-access'
$design = Get-Content (Join-Path $p06 'config\privileged-access-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
. (Join-Path $p06 'scripts\powershell\_PimPolicy.ps1')
Connect-Danotech -Scopes 'RoleManagementPolicy.ReadWrite.Directory', 'Policy.Read.All', 'User.Read.All'

$ca102 = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/policies').value | Where-Object { $_.displayName -like 'CA102-*' }
if (-not $ca102 -or $ca102.state -ne 'enabled') { throw 'CA102 must be ENABLED first, or activation would only need any sign-in (walkthrough Step 9).' }

foreach ($s in $design.roleSettings | Where-Object profile -eq 'T0-Approval') {
    $policyId = Get-PimPolicyId -ScopeType DirectoryRole -ScopeId '/' -RoleDefinitionId $s.roleTemplateId
    $rules = Get-PimRules $policyId
    $en = $rules['Enablement_EndUser_Assignment']
    $en.enabledRules = @($en.enabledRules | Where-Object { $_ -ne 'MultiFactorAuthentication' })
    Update-PimRule $policyId $en
    $ac = $rules['AuthenticationContext_EndUser_Assignment']
    $ac.isEnabled = $true; $ac.claimValue = $ContextId
    Update-PimRule $policyId $ac
    $diffs = @(Test-PimPolicy $policyId $design.roleSettingProfiles.'T0-Approval' @(Resolve-UserIds $s.approvers))
    $now = (Get-PimRules $policyId)['AuthenticationContext_EndUser_Assignment']
    if ($diffs -or -not $now.isEnabled) { Write-Host "$($s.role): $($diffs -join '; ')" -ForegroundColor Red }
    else { Write-Host "$($s.role): activation now requires authentication context $($now.claimValue) (+ justification, ticket, approval)" -ForegroundColor Green }
}
