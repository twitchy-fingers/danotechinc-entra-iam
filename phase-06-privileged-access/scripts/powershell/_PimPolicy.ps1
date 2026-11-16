<#
    Shared helpers for PIM role settings (dot-sourced by scripts 02, 03 and 05).

    PIM stores each role's settings as a "role management policy" made of rules:
      Expiration_EndUser_Assignment           max activation duration
      Enablement_EndUser_Assignment           what activation requires (MFA, justification, ticket)
      AuthenticationContext_EndUser_Assignment Conditional Access authentication context (Phase 07)
      Approval_EndUser_Assignment             approval and approvers
      Expiration_Admin_Eligibility            how long an eligible assignment may last
      Expiration_Admin_Assignment             how long an active assignment may last
      Notification_Admin_EndUser_Assignment   who is emailed when someone activates

    Rules are read, changed and written back whole (GET -> modify -> PATCH), so fields
    these scripts don't manage are preserved exactly as the portal or Microsoft set them.
#>

function Get-PimPolicyId {
    param([Parameter(Mandatory)][ValidateSet('DirectoryRole', 'Group')] [string] $ScopeType,
          [Parameter(Mandatory)] [string] $ScopeId,          # '/' for directory roles, group id for groups
          [Parameter(Mandatory)] [string] $RoleDefinitionId) # role template id, or 'member' for groups
    $f = "scopeId eq '$ScopeId' and scopeType eq '$ScopeType' and roleDefinitionId eq '$RoleDefinitionId'"
    $a = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/policies/roleManagementPolicyAssignments?`$filter=$f").value | Select-Object -First 1
    if (-not $a) { throw "No PIM policy found for $ScopeType $ScopeId / $RoleDefinitionId" }
    $a.policyId
}

function Get-PimRules([string] $PolicyId) {
    $rules = @{}
    foreach ($r in (Invoke-MgGraphRequest -Method GET -Uri "v1.0/policies/roleManagementPolicies/$PolicyId/rules").value) { $rules[$r.id] = $r }
    $rules
}

function Update-PimRule([string] $PolicyId, [hashtable] $Rule) {
    $body = $Rule | ConvertTo-Json -Depth 20
    Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/policies/roleManagementPolicies/$PolicyId/rules/$($Rule.id)" -Body $body -ContentType 'application/json' | Out-Null
}

function Resolve-UserIds([string[]] $Upns) {
    foreach ($u in $Upns) { (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($u)?`$select=id").id }
}

function Set-PimPolicy {
    <# Applies a settings profile (from privileged-access-design.json) to one policy. #>
    param([string] $PolicyId, $Profile, [string[]] $ApproverIds, [string] $NotifyMail)
    $rules = Get-PimRules $PolicyId

    $r = $rules['Expiration_EndUser_Assignment'];  $r.maximumDuration = $Profile.maxActivation; Update-PimRule $PolicyId $r

    $ctx = $rules['AuthenticationContext_EndUser_Assignment']
    $want = @($Profile.activationRequires)
    if ($ctx -and $ctx.isEnabled) { $want = @($want | Where-Object { $_ -ne 'MultiFactorAuthentication' }) }  # mutually exclusive (Phase 07)
    $r = $rules['Enablement_EndUser_Assignment'];  $r.enabledRules = $want; Update-PimRule $PolicyId $r

    $r = $rules['Expiration_Admin_Eligibility'];   $r.isExpirationRequired = $true; $r.maximumDuration = $Profile.eligibilityMax; Update-PimRule $PolicyId $r
    $r = $rules['Expiration_Admin_Assignment'];    $r.isExpirationRequired = $true; $r.maximumDuration = $Profile.activeAssignmentMax; Update-PimRule $PolicyId $r

    $r = $rules['Approval_EndUser_Assignment']
    $r.setting.isApprovalRequired = [bool]$Profile.approval
    if ($Profile.approval) {
        $r.setting.isRequestorJustificationRequired = $true
        $r.setting.approvalMode = 'SingleStage'
        $r.setting.approvalStages = @(@{
            approvalStageTimeOutInDays = 1; isApproverJustificationRequired = $true
            escalationTimeInMinutes = 0; isEscalationEnabled = $false; escalationApprovers = @()
            primaryApprovers = @($ApproverIds | ForEach-Object { @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = $_ } })
        })
    }
    Update-PimRule $PolicyId $r

    if ($NotifyMail -and $rules['Notification_Admin_EndUser_Assignment']) {
        $r = $rules['Notification_Admin_EndUser_Assignment']
        $r.notificationRecipients = @($NotifyMail); $r.isDefaultRecipientsEnabled = $true
        Update-PimRule $PolicyId $r
    }
}

function Test-PimPolicy {
    <# Returns a list of differences between a policy and a settings profile. Empty = matches. #>
    param([string] $PolicyId, $Profile, [string[]] $ApproverIds)
    $rules = Get-PimRules $PolicyId
    $d = @()
    $max = $rules['Expiration_EndUser_Assignment'].maximumDuration
    if ($max -ne $Profile.maxActivation) { $d += "max activation is $max, expected $($Profile.maxActivation)" }

    $have = @($rules['Enablement_EndUser_Assignment'].enabledRules)
    $ctxOn = [bool]$rules['AuthenticationContext_EndUser_Assignment'].isEnabled
    foreach ($w in $Profile.activationRequires) {
        if ($w -eq 'MultiFactorAuthentication' -and $ctxOn) { continue }   # authentication context replaces plain MFA
        if ($have -notcontains $w) { $d += "activation doesn't require $w" }
    }
    $el = $rules['Expiration_Admin_Eligibility']
    if (-not $el.isExpirationRequired) { $d += 'permanent eligible assignments are allowed' }
    $as = $rules['Expiration_Admin_Assignment']
    if (-not $as.isExpirationRequired) { $d += 'permanent ACTIVE assignments are allowed' }

    $ap = $rules['Approval_EndUser_Assignment'].setting
    if ([bool]$ap.isApprovalRequired -ne [bool]$Profile.approval) { $d += "approval required is $($ap.isApprovalRequired), expected $($Profile.approval)" }
    if ($Profile.approval) {
        $got = @($ap.approvalStages | ForEach-Object { $_.primaryApprovers } | ForEach-Object { $_.userId ?? $_.id })
        foreach ($id in $ApproverIds) { if ($got -notcontains $id) { $d += "approver $id missing" } }
    }
    $d
}
