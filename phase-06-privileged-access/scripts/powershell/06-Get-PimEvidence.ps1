#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Exports Phase 06 evidence: eligible assignments, role settings, and every activation request
    (who, which role, when, for how long, justification, ticket, approval outcome).
#>
param([datetime] $Since = (Get-Date).AddDays(-30))
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\privileged-access-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
. (Join-Path $PSScriptRoot '_PimPolicy.ps1')
Connect-Danotech -Scopes 'RoleManagement.Read.Directory', 'RoleEligibilitySchedule.Read.Directory', 'RoleAssignmentSchedule.Read.Directory',
    'RoleManagementPolicy.Read.Directory', 'PrivilegedAccess.Read.AzureADGroup', 'Group.Read.All', 'User.Read.All'
$stamp = Get-Date -Format 'yyyyMMdd'; $ev = Join-Path $phase 'evidence'
$names = @{}; (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/roleManagement/directory/roleDefinitions?$select=templateId,displayName').value | ForEach-Object { $names[$_.templateId] = $_.displayName }

(Invoke-MgGraphRequest -Method GET -Uri 'v1.0/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal').value |
    ForEach-Object { [pscustomobject]@{ Account = $_.principal.userPrincipalName; Role = $names[$_.roleDefinitionId]; Scope = $_.directoryScopeId; Ends = $_.endDateTime } } |
    Sort-Object Role, Account | Export-Csv (Join-Path $ev "$stamp-eligible-assignments.csv") -NoTypeInformation -Encoding utf8

$since = $Since.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
(Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleAssignmentScheduleRequests?`$filter=createdDateTime ge $since&`$expand=principal").value |
    Where-Object action -in 'selfActivate', 'selfDeactivate' |
    ForEach-Object { [pscustomobject]@{ Created = $_.createdDateTime; Account = $_.principal.userPrincipalName; Role = $names[$_.roleDefinitionId]; Action = $_.action
        Status = $_.status; Duration = $_.scheduleInfo.expiration.duration; Justification = $_.justification; Ticket = $_.ticketInfo.ticketNumber } } |
    Sort-Object Created | Export-Csv (Join-Path $ev "$stamp-role-activations.csv") -NoTypeInformation -Encoding utf8

$rows = foreach ($s in $design.roleSettings) {
    $rules = Get-PimRules (Get-PimPolicyId -ScopeType DirectoryRole -ScopeId '/' -RoleDefinitionId $s.roleTemplateId)
    [pscustomobject]@{ Role = $s.role; Profile = $s.profile; MaxActivation = $rules['Expiration_EndUser_Assignment'].maximumDuration
        Requires = ($rules['Enablement_EndUser_Assignment'].enabledRules -join ','); AuthContext = $rules['AuthenticationContext_EndUser_Assignment'].claimValue
        Approval = $rules['Approval_EndUser_Assignment'].setting.isApprovalRequired; EligibilityMax = $rules['Expiration_Admin_Eligibility'].maximumDuration }
}
$rows | Export-Csv (Join-Path $ev "$stamp-pim-role-settings.csv") -NoTypeInformation -Encoding utf8
$rows | Format-Table -AutoSize
Write-Host "Evidence written to $ev" -ForegroundColor Green
