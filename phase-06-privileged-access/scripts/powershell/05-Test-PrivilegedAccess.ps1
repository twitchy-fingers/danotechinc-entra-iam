#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    The Phase 06 control test: proves privileged access matches the policy. Read-only unless -Remediate.

.DESCRIPTION
    Checks, and reports every finding:
      PA-01  No PERMANENT active privileged directory role except the two break-glass accounts
      PA-02  No privileged role (eligible or active) on a DAILY account
      PA-03  Eligible assignments match the design exactly: nothing missing, nothing extra
      PA-04  No contractor or intern owns an admin account
      PA-05  No orphaned admin account: if the person's daily account is disabled or gone
             (a leaver), their adm. account must be disabled too. -Remediate disables it.
      PA-06  Every PIM-managed group has eligible members only (no standing members)
    Standing read-only roles (Global Reader, Security Reader) are excluded: they're High, not
    Privileged, and handled by script 04.
    Exit code 1 on any finding, so it can run on a schedule and alert.
#>
param([switch] $Remediate)
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\privileged-access-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'RoleManagement.Read.Directory', 'RoleEligibilitySchedule.Read.Directory', 'RoleAssignmentSchedule.Read.Directory',
    'PrivilegedAccess.Read.AzureADGroup', 'Group.Read.All', 'User.ReadWrite.All', 'AdministrativeUnit.Read.All'

$findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding($id, $msg) { $findings.Add([pscustomobject]@{ Check = $id; Finding = $msg }) }

$readerIds = @($design.standingReaderRoles.roleTemplateId)
$privIds   = @($design.roleSettings.roleTemplateId) + @(
    '7be44c8a-adaf-4e2a-84d6-ab2649e08a13','194ae4cb-b126-40b2-bd5b-6091b380977d','158c047a-c907-4556-b7ef-446551a6b5f7',
    'c4e39bd9-1100-46d3-8c65-fb160da0071f','fdd7a751-b60b-444a-984c-02652fe8fa1c','29232cdf-9323-42fd-ade2-1d097af3e4de',
    'f28a1f50-f6e7-4571-818b-6a12f2af6b6c','b0f54661-2d74-4c50-afa3-1ec803f12efe')   # also flag privileged roles nobody should hold
$names = @{}; (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/roleManagement/directory/roleDefinitions?$select=templateId,displayName').value | ForEach-Object { $names[$_.templateId] = $_.displayName }

$bg = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($design.breakGlassGroup)'").value[0]
$bgIds = @((Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$($bg.id)/members?`$select=id").value.id)

function Get-All($uri) { $all = @(); while ($uri) { $p = Invoke-MgGraphRequest -Method GET -Uri $uri; $all += $p.value; $uri = $p.'@odata.nextLink' }; $all }
$users = @{}; foreach ($u in (Get-All 'v1.0/users?$select=id,userPrincipalName,employeeId,employeeType,accountEnabled&$top=999')) { $users[$u.id] = $u }
$active   = Get-All 'v1.0/roleManagement/directory/roleAssignmentScheduleInstances?$expand=principal'
$eligible = Get-All 'v1.0/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal'

# PA-01 permanent active privileged roles
foreach ($a in $active | Where-Object { $privIds -contains $_.roleDefinitionId -and $_.assignmentType -eq 'Assigned' }) {
    if ($bgIds -contains $a.principalId) { continue }
    if (-not $a.endDateTime) { Add-Finding 'PA-01' "$($users[$a.principalId].userPrincipalName ?? $a.principal.displayName ?? $a.principalId) holds $($names[$a.roleDefinitionId]) PERMANENTLY active" }
}
# PA-02 privileged roles on daily accounts
foreach ($x in @($active) + @($eligible) | Where-Object { $privIds -contains $_.roleDefinitionId }) {
    $p = $users[$x.principalId]
    if (-not $p -or $bgIds -contains $x.principalId) { continue }          # not a user (e.g. a group), or break-glass
    if ($p.employeeType -ne 'AdminAccount') { Add-Finding 'PA-02' "Daily account $($p.userPrincipalName) has $($names[$x.roleDefinitionId])" }
}
# PA-03 eligibility matches design
$au = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/directory/administrativeUnits?`$filter=displayName eq '$($design.administrativeUnit.name)'").value | Select-Object -First 1
$want = @{}
foreach ($e in $design.directoryEligibility) {
    $scope = if ($e.scope -eq 'AU-Workforce') { "/administrativeUnits/$($au.id)" } else { '/' }
    $want["$($e.adminUpn.ToLower())|$($e.roleTemplateId)|$scope"] = $e.role
}
$have = @{}
foreach ($e in $eligible | Where-Object { $privIds -contains $_.roleDefinitionId -and $users[$_.principalId] }) { $have["$($users[$e.principalId].userPrincipalName.ToLower())|$($e.roleDefinitionId)|$($e.directoryScopeId)"] = $true }
foreach ($k in $want.Keys) { if (-not $have.ContainsKey($k)) { Add-Finding 'PA-03' "Missing eligibility: $($k.Split('|')[0]) : $($want[$k])" } }
foreach ($k in $have.Keys) { if (-not $want.ContainsKey($k)) { Add-Finding 'PA-03' "Eligibility not in design: $($k.Split('|')[0]) : $($names[$k.Split('|')[1]]) at $($k.Split('|')[2])" } }

# PA-04 / PA-05 admin accounts vs their owners' daily accounts
foreach ($adm in $users.Values | Where-Object employeeType -eq 'AdminAccount') {
    $daily = $users.Values | Where-Object { $_.employeeId -eq $adm.employeeId -and $_.employeeType -ne 'AdminAccount' } | Select-Object -First 1
    if ($daily -and $daily.employeeType -in 'Contractor', 'Intern') { Add-Finding 'PA-04' "$($adm.userPrincipalName) belongs to a $($daily.employeeType)" }
    if ($adm.accountEnabled -and (-not $daily -or -not $daily.accountEnabled)) {
        Add-Finding 'PA-05' "$($adm.userPrincipalName) is enabled but its owner's daily account is $(if ($daily) { 'disabled' } else { 'gone' })"
        if ($Remediate) {
            Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/users/$($adm.id)" -Body @{ accountEnabled = $false }
            Invoke-MgGraphRequest -Method POST -Uri "v1.0/users/$($adm.id)/revokeSignInSessions" | Out-Null
            Write-Host "  remediated: disabled $($adm.userPrincipalName) and revoked its sessions" -ForegroundColor Yellow
        }
    }
}
# PA-06 PIM groups: no standing (permanent, non-PIM) members
foreach ($g in $design.pimGroups) {
    $grp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($g.groupName)'").value | Select-Object -First 1
    if (-not $grp) { Add-Finding 'PA-06' "$($g.groupName) doesn't exist"; continue }
    $inst = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=groupId eq '$($grp.id)'").value
    foreach ($i in $inst | Where-Object { $_.accessId -eq 'member' -and -not $_.endDateTime }) { Add-Finding 'PA-06' "$($g.groupName) has a permanent member ($($i.principalId))" }
}

$stamp = Get-Date -Format 'yyyyMMdd'
$findings | Export-Csv (Join-Path $phase "evidence\$stamp-privileged-access-test.csv") -NoTypeInformation -Encoding utf8
if ($findings.Count) { $findings | Format-Table -AutoSize -Wrap; Write-Host "$($findings.Count) finding(s)." -ForegroundColor Red; exit 1 }
Write-Host 'PASS: no standing privileged access outside break-glass; eligibility matches the design; no orphaned admin accounts.' -ForegroundColor Green
