#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Applies PIM role settings to the 8 directory roles, and checks the one you configured by hand.

.DESCRIPTION
    Global Administrator's settings are configured in the portal (walkthrough Step 5) so you see
    every option PIM offers. This script:
      - CHECKS Global Administrator against the T0-Approval profile and reports differences
        (it doesn't overwrite your work unless you pass -Repair)
      - APPLIES the design's profile to the other 7 roles, then re-reads and checks each

    Profiles (config\privileged-access-design.json):
      T0-Approval      GA, Privileged Role Admin: 2h, MFA + justification + ticket, APPROVAL
      T1-SelfActivate  User, CA, App, Identity Governance Admin, Security Operator: 4h, MFA + justification
      T2-Helpdesk      Helpdesk Admin: 8h (a shift), MFA + justification
    All: eligibility expires after 180 days (no permanent eligibility), active assignments after 30.
    Activations notify the CISO (his mail attribute, set in Phase 04 Step 8).
#>
param([switch] $Repair)
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\privileged-access-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
. (Join-Path $PSScriptRoot '_PimPolicy.ps1')
Connect-Danotech -Scopes 'RoleManagementPolicy.ReadWrite.Directory', 'User.Read.All'

$notify = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($design.activationNotifyUpn)?`$select=mail").mail
if (-not $notify) { Write-Host "$($design.activationNotifyUpn) has no mail attribute; activation emails go to default recipients only." -ForegroundColor Yellow }

$fail = 0
foreach ($s in $design.roleSettings) {
    $profile = $design.roleSettingProfiles.($s.profile)
    $approvers = if ($s.approvers) { @(Resolve-UserIds $s.approvers) } else { @() }
    $policyId = Get-PimPolicyId -ScopeType DirectoryRole -ScopeId '/' -RoleDefinitionId $s.roleTemplateId

    if ($s.builtInPortal -and -not $Repair) {
        $diffs = @(Test-PimPolicy $policyId $profile $approvers)
        if ($diffs) {
            $fail++
            Write-Host "$($s.role) (built in the portal): DIFFERS from $($s.profile)" -ForegroundColor Red
            $diffs | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
        } else { Write-Host "$($s.role) (built in the portal): matches $($s.profile)" -ForegroundColor Green }
        continue
    }
    Set-PimPolicy $policyId $profile $approvers $notify
    $diffs = @(Test-PimPolicy $policyId $profile $approvers)
    if ($diffs) { $fail++; Write-Host "$($s.role): applied but still differs: $($diffs -join '; ')" -ForegroundColor Red }
    else { Write-Host "$($s.role): $($s.profile) applied and verified" -ForegroundColor Green }
}
if ($fail) { Write-Host "`nFix the differences in the portal (PIM > Microsoft Entra roles > Settings), or rerun with -Repair." -ForegroundColor Yellow; exit 1 }
