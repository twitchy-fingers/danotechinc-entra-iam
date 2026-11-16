#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Creates every eligible assignment in the design: directory roles and PIM-managed groups.

.DESCRIPTION
    Built by hand first (walkthrough Steps 3, 6 and 7): AU-Workforce, adm.daniel.opara's
    eligible Global Administrator, and GRP-ROLE-PIM-WP-ADMIN with Ngozi Balogun eligible.
    This script does the bulk, and checks that the hand-built items exist:

    1. Directory roles: 23 more eligible assignments (180 days). Helpdesk Administrator is
       scoped to the AU-Workforce administrative unit, so helpdesk staff can only act on
       workforce accounts: never on admin or break-glass accounts.
    2. PIM-managed groups: creates the other 4 role-assignable GRP-ROLE-PIM-* groups, applies the
       App-Admin-Group settings to all 5, and makes their members ELIGIBLE (not members). Phase 08
       connects each group to its application's admin role.
    3. Refuses to make anyone eligible who isn't an admin account (employeeType = AdminAccount).

    Run as adm.adaeze.nwosu with Privileged Role Administrator activated.
#>
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\privileged-access-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
. (Join-Path $PSScriptRoot '_PimPolicy.ps1')
Connect-Danotech -Scopes 'RoleEligibilitySchedule.ReadWrite.Directory', 'RoleManagementPolicy.ReadWrite.Directory',
    'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup', 'RoleManagementPolicy.ReadWrite.AzureADGroup',
    'Group.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'User.Read.All', 'AdministrativeUnit.Read.All'

$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$userCache = @{}
function Get-AdminUser([string] $upn) {
    if (-not $userCache[$upn]) {
        $u = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($upn)?`$select=id,employeeType"
        if ($u.employeeType -ne 'AdminAccount') { throw "$upn isn't an admin account (employeeType '$($u.employeeType)'). Refusing." }
        $userCache[$upn] = $u
    }
    $userCache[$upn]
}

# --- Hand-built prerequisites ------------------------------------------------
$au = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/directory/administrativeUnits?`$filter=displayName eq '$($design.administrativeUnit.name)'").value | Select-Object -First 1
if (-not $au) { throw "$($design.administrativeUnit.name) not found. Build it in the portal first (walkthrough Step 3)." }
if ($au.membershipRule -ne $design.administrativeUnit.rule) { Write-Host "AU-Workforce rule differs from the design:`n  live:   $($au.membershipRule)`n  design: $($design.administrativeUnit.rule)" -ForegroundColor Yellow }

# --- 1. Directory role eligibility ---------------------------------------------
Write-Host "`nDirectory roles" -ForegroundColor Cyan
foreach ($e in $design.directoryEligibility) {
    $u = Get-AdminUser $e.adminUpn
    $scope = if ($e.scope -eq 'AU-Workforce') { "/administrativeUnits/$($au.id)" } else { '/' }
    $have = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleEligibilitySchedules?`$filter=principalId eq '$($u.id)' and roleDefinitionId eq '$($e.roleTemplateId)'").value |
        Where-Object directoryScopeId -eq $scope
    if ($have) { Write-Host "  exists   $($e.adminUpn) : $($e.role) [$($e.scope)]"; continue }
    if ($e.role -eq 'Global Administrator') { Write-Host "  MISSING  $($e.adminUpn) : Global Administrator. Make it eligible in the portal (Step 6)." -ForegroundColor Red; continue }
    Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleEligibilityScheduleRequests' -Body @{
        action = 'adminAssign'; principalId = $u.id; roleDefinitionId = $e.roleTemplateId; directoryScopeId = $scope
        justification = "Phase 06: $($e.modelRole) per role model (ADR-0012)"
        scheduleInfo = @{ startDateTime = $now; expiration = @{ type = 'afterDuration'; duration = 'P180D' } } } | Out-Null
    Write-Host "  added    $($e.adminUpn) : $($e.role) [$($e.scope)]" -ForegroundColor Green
}

# --- 2. PIM-managed groups (application admin roles) ---------------------------------
Write-Host "`nPIM-managed groups" -ForegroundColor Cyan
$profile = $design.roleSettingProfiles.'App-Admin-Group'
foreach ($g in $design.pimGroups) {
    $grp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($g.groupName)'&`$select=id,isAssignableToRole").value | Select-Object -First 1
    if (-not $grp) {
        $grp = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/groups' -Body @{
            displayName = $g.groupName; mailEnabled = $false; securityEnabled = $true; mailNickname = $g.groupName.ToLower()
            isAssignableToRole = $true
            description = "Role $($g.modelRole): $($g.grants), just-in-time via PIM for Groups. Owner: $($g.owner). Members are ELIGIBLE only. Connected in $($g.connectedIn)." }
        Write-Host "  created  $($g.groupName)" -ForegroundColor Green
        Start-Sleep -Seconds 10
    } elseif (-not $grp.isAssignableToRole) { Write-Host "  WARNING  $($g.groupName) isn't role-assignable: anyone with Groups Administrator could change it." -ForegroundColor Yellow }

    foreach ($upn in $g.eligibleMembers) {
        $u = Get-AdminUser $upn
        $have = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=groupId eq '$($grp.id)' and principalId eq '$($u.id)'").value
        if ($have) { Write-Host "  exists   $upn eligible for $($g.groupName)"; continue }
        Invoke-MgGraphRequest -Method POST -Uri 'v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests' -Body @{
            accessId = 'member'; principalId = $u.id; groupId = $grp.id; action = 'adminAssign'
            justification = "Phase 06: $($g.modelRole) per role model (ADR-0012)"
            scheduleInfo = @{ startDateTime = $now; expiration = @{ type = 'afterDuration'; duration = 'P180D' } } } | Out-Null
        Write-Host "  added    $upn eligible for $($g.groupName)" -ForegroundColor Green
    }
    # Group settings exist once the group is managed by PIM (after its first eligibility)
    $policyId = Get-PimPolicyId -ScopeType Group -ScopeId $grp.id -RoleDefinitionId 'member'
    Set-PimPolicy $policyId $profile @() $null
    $diffs = @(Test-PimPolicy $policyId $profile @())
    if ($diffs) { Write-Host "  SETTINGS $($g.groupName): $($diffs -join '; ')" -ForegroundColor Red } else { Write-Host "  settings $($g.groupName): App-Admin-Group verified" }
}

if ($design.deferredToPhase09) {
    Write-Host "`nDeferred to Phase 09 (Azure roles): $(($design.deferredToPhase09 | ForEach-Object { "$($_.adminUpn) $($_.entitlement)" }) -join ', ')" -ForegroundColor DarkGray
}
