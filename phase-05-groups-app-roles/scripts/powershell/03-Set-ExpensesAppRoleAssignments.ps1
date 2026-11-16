#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Checks the Danotech Expenses app you built in the portal, then assigns its remaining
    app roles to groups from the Phase 03 model.

.DESCRIPTION
    You register the app, create its roles and secret, and make the first role assignment in
    the portal (walkthrough Steps 5-6). This script then:

    1. VERIFIES the portal work against the design:
         single-tenant; localhost redirect URI; no implicit grant; all five role values present,
         enabled and assignable to users; Graph User.Read requested AND admin-consented;
         "Assignment required" on; client secret no longer than 31 days.
    2. ASSIGNS every remaining role-to-group pair derived from the model: each role whose
       entitlements include an EXP-* entitlement gets the matching app role. Nothing is hand-picked.
    3. Saves the app's IDs to config\expenses-app.local.json (git-ignored) for the evidence script.

    Exit code 1 if any check fails, so problems are fixed before the app goes live.
#>
param([string] $AppName = 'app-danotech-expenses')
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$repo  = Resolve-Path (Join-Path $phase '..')
. (Join-Path $repo 'scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Application.Read.All', 'AppRoleAssignment.ReadWrite.All', 'Group.Read.All', 'DelegatedPermissionGrant.Read.All'

$cfg = Get-Content (Join-Path $phase 'config\expenses-app-roles.json') -Raw | ConvertFrom-Json
$fail = 0
function Check([bool] $ok, [string] $what) {
    if ($ok) { Write-Host "  PASS  $what" -ForegroundColor Green } else { Write-Host "  FAIL  $what" -ForegroundColor Red; $script:fail++ }
}

$app = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/applications?`$filter=displayName eq '$AppName'").value | Select-Object -First 1
if (-not $app) { throw "App registration '$AppName' not found. Create it in the portal first (walkthrough Step 5)." }
$sp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '$($app.appId)'").value | Select-Object -First 1
$graphSp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'").value[0]
$userReadId = ($graphSp.oauth2PermissionScopes | Where-Object value -eq 'User.Read').id

Write-Host "`nChecking the portal configuration of $AppName" -ForegroundColor Cyan
Check ($app.signInAudience -eq 'AzureADMyOrg') 'Single tenant (accounts in DanotechInc only)'
Check ($app.web.redirectUris -contains 'http://localhost:5000/auth/callback') 'Web redirect URI http://localhost:5000/auth/callback'
Check (-not $app.web.implicitGrantSettings.enableIdTokenIssuance -and -not $app.web.implicitGrantSettings.enableAccessTokenIssuance) 'Implicit grant off (authorization code flow only)'
foreach ($r in $cfg.appRoles) {
    $live = $app.appRoles | Where-Object value -eq $r.value
    Check ($live -and $live.isEnabled -and ($live.allowedMemberTypes -contains 'User')) "App role $($r.value) exists, enabled, assignable to users"
}
$requested = $app.requiredResourceAccess | Where-Object resourceAppId -eq '00000003-0000-0000-c000-000000000000'
Check ([bool]($requested.resourceAccess | Where-Object { $_.id -eq $userReadId -and $_.type -eq 'Scope' })) 'Microsoft Graph User.Read (delegated) requested'
Check ([bool]$sp) 'Enterprise app (service principal) exists'
if ($sp) {
    Check ([bool]$sp.appRoleAssignmentRequired) 'Assignment required = Yes'
    $grant = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($sp.id)'").value |
        Where-Object { $_.consentType -eq 'AllPrincipals' -and $_.resourceId -eq $graphSp.id -and $_.scope -match '\bUser\.Read\b' }
    Check ([bool]$grant) 'Admin consent granted for User.Read'
}
$secrets = @($app.passwordCredentials)
Check ($secrets.Count -ge 1) 'A client secret exists'
foreach ($p in $secrets) {
    $days = ([datetime]$p.endDateTime - [datetime]$p.startDateTime).TotalDays
    Check ($days -le 31) ("Secret '{0}' lifetime {1:N0} days (policy: 30 days until Phase 10 removes it)" -f $p.displayName, $days)
}
if ($fail) { Write-Host "`n$fail check(s) failed. Fix them in the portal and rerun." -ForegroundColor Red; exit 1 }

# Assign the remaining roles from the model
Write-Host "`nAssigning app roles to groups from the Phase 03 model" -ForegroundColor Cyan
$roleByEnt = @{}; foreach ($r in $cfg.appRoles) { $roleByEnt[$r.entitlementId] = ($app.appRoles | Where-Object value -eq $r.value) }
$model = Get-Content (Join-Path $repo 'phase-03-rbac-design\generated\dynamic-group-rules.json') -Raw -Encoding utf8 | ConvertFrom-Json
$assigned = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo?`$top=999").value
$expectedPairs = 0
foreach ($m in $model) {
    foreach ($e in ($m.entitlements | Where-Object { $roleByEnt.ContainsKey($_) })) {
        $role = $roleByEnt[$e]
        $grp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($m.groupName)'&`$select=id").value | Select-Object -First 1
        if (-not $grp) { Write-Host "  skip  $($m.groupName) -> $($role.value): $($m.membershipType) group, built in a later phase" -ForegroundColor DarkGray; continue }
        $expectedPairs++
        if ($assigned | Where-Object { $_.principalId -eq $grp.id -and $_.appRoleId -eq $role.id }) {
            Write-Host "  exists $($m.groupName) -> $($role.value)"; continue
        }
        Invoke-MgGraphRequest -Method POST -Uri "v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo" -Body @{
            principalId = $grp.id; resourceId = $sp.id; appRoleId = $role.id } | Out-Null
        Write-Host "  added  $($m.groupName) -> $($role.value)" -ForegroundColor Green
    }
}
# Anything assigned in the portal that the model doesn't call for?
$assigned = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo?`$top=999").value
$roleValue = @{}; foreach ($r in $app.appRoles) { $roleValue[$r.id] = $r.value }
$modelPairs = foreach ($m in $model) { foreach ($e in ($m.entitlements | Where-Object { $roleByEnt.ContainsKey($_) })) { "$($m.groupName)|$($roleByEnt[$e].value)" } }
foreach ($a in $assigned) {
    if ($modelPairs -notcontains "$($a.principalDisplayName)|$($roleValue[$a.appRoleId])") {
        Write-Host "  NOT IN MODEL: $($a.principalDisplayName) -> $($roleValue[$a.appRoleId]). Remove it in the portal, or add it to the model." -ForegroundColor Yellow
    }
}
Write-Host "$expectedPairs role-to-group assignments expected; $(@($assigned).Count) present." -ForegroundColor Cyan

@{ appId = $app.appId; applicationObjectId = $app.id; servicePrincipalId = $sp.id } | ConvertTo-Json |
    Set-Content (Join-Path $phase 'config\expenses-app.local.json') -Encoding utf8
