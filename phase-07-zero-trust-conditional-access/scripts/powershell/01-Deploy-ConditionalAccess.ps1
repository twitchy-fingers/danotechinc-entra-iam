#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Deploys the Phase 07 Conditional Access policies from policies\*.json, and checks existing ones.

.DESCRIPTION
    Policies are matched to the tenant by their NUMBER (CA002, CA100...), per the naming convention,
    so a renamed policy is still recognised.

    New policies:      created in REPORT-ONLY. Nothing is enforced until you decide (rollout rings).
    Existing policies: compared with the JSON (conditions, grant, session; not state or ring users)
                       and differences reported. CA002 is built by hand in the portal; CA100 exists
                       from Phase 01 with the old MFA grant. -UpdateExisting brings them in line,
                       keeping their current state and ring.

    Placeholders resolved at deploy time (no tenant IDs in Git):
      {{BREAKGLASS_GROUP_ID}} {{ADMIN_ACCOUNTS_GROUP_ID}} {{ADMIN_ONBOARDING_GROUP_ID}} {{RING0_GROUP_ID}}
      {{NL_OPERATING_COUNTRIES_ID}} {{AS_ONBOARDING_ID}} {{ADMIN_ALLOWED_APP_IDS}} (expands to a list)

    Creates GRP-ASG-CA-Ring0 (the IAM team) and GRP-CA-Exclude-AdminOnboarding (empty) if missing.
    Refuses to run unless the break-glass exclusion group has two members.
    Run as adm.adaeze.nwosu with Conditional Access Administrator activated.
.EXAMPLE
    ./01-Deploy-ConditionalAccess.ps1
    ./01-Deploy-ConditionalAccess.ps1 -UpdateExisting -Only CA100
#>
param([switch] $UpdateExisting, [string[]] $Only)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$cfg   = Get-Content (Join-Path $phase 'config\zero-trust-config.json') -Raw | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'Application.Read.All', 'Group.ReadWrite.All', 'User.Read.All'

function Get-GroupId([string] $name) {
    ((Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$name'&`$select=id").value | Select-Object -First 1).id
}
function Ensure-Group([string] $name, [string] $desc, [string[]] $memberUpns) {
    $id = Get-GroupId $name
    if (-not $id) {
        $id = (Invoke-MgGraphRequest -Method POST -Uri 'v1.0/groups' -Body @{ displayName = $name; description = $desc; mailEnabled = $false; securityEnabled = $true; mailNickname = $name.ToLower() }).id
        Write-Host "Created $name" -ForegroundColor Green; Start-Sleep -Seconds 10
        foreach ($u in $memberUpns) {
            $uid = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($u)?`$select=id").id
            Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$id/members/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$uid" }
        }
    }
    $id
}

# --- Lockout guard ----------------------------------------------------------
$bg = Get-GroupId $cfg.groups.breakGlass
$bgCount = @((Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$bg/members?`$select=id").value).Count
if ($bgCount -lt 2) { throw "Break-glass exclusion group has $bgCount member(s); expected 2. Aborting." }

# --- Resolve referenced objects -------------------------------------------------
$nl = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/namedLocations').value | Where-Object displayName -eq $cfg.namedLocation.name
if (-not $nl) { throw "Named location $($cfg.namedLocation.name) not found. Build it in the portal (walkthrough Step 3)." }
$as = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/authenticationStrength/policies').value | Where-Object displayName -eq $cfg.authenticationStrength.name
if (-not $as) { throw "Authentication strength $($cfg.authenticationStrength.name) not found (walkthrough Step 4)." }
$ctx = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/authenticationContextClassReferences').value | Where-Object { $_.id -eq $cfg.authenticationContext.id -and $_.isAvailable }
if (-not $ctx) { throw "Authentication context $($cfg.authenticationContext.id) not found or not published to apps (walkthrough Step 5)." }
$adminGrp = Get-GroupId $cfg.groups.adminAccounts
if (-not $adminGrp) { throw "$($cfg.groups.adminAccounts) not found (Phase 06 script 01)." }
$ring0 = Ensure-Group $cfg.groups.ring0.name $cfg.groups.ring0.description $cfg.groups.ring0.members
$onb   = Ensure-Group $cfg.groups.adminOnboarding.name $cfg.groups.adminOnboarding.description @()
$appIds = ($cfg.adminAllowedApps | ForEach-Object { "`"$($_.appId)`"" }) -join ','

$map = @{
    '{{BREAKGLASS_GROUP_ID}}' = $bg; '{{ADMIN_ACCOUNTS_GROUP_ID}}' = $adminGrp; '{{ADMIN_ONBOARDING_GROUP_ID}}' = $onb
    '{{RING0_GROUP_ID}}' = $ring0; '{{NL_OPERATING_COUNTRIES_ID}}' = $nl.id; '{{AS_ONBOARDING_ID}}' = $as.id
}

# --- Comparison: the parts of a policy that define WHAT it does ---------------------------
function Get-Signature($p, [bool] $ignoreUsers) {
    $c = $p.conditions; $g = $p.grantControls; $s = $p.sessionControls
    $sig = [ordered]@{
        apps        = (@($c.applications.includeApplications) | Sort-Object) -join ','
        appsEx      = (@($c.applications.excludeApplications) | Sort-Object) -join ','
        userActions = (@($c.applications.includeUserActions) | Sort-Object) -join ','
        authContext = (@($c.applications.includeAuthenticationContextClassReferences) | Sort-Object) -join ','
        exGroups    = (@($c.users.excludeGroups) | Sort-Object) -join ','
        roles       = (@($c.users.includeRoles) | Sort-Object) -join ','
        locIn       = (@($c.locations.includeLocations) | Sort-Object) -join ','
        locEx       = (@($c.locations.excludeLocations) | Sort-Object) -join ','
        signInRisk  = (@($c.signInRiskLevels) | Sort-Object) -join ','
        userRisk    = (@($c.userRiskLevels) | Sort-Object) -join ','
        authFlows   = "$($c.authenticationFlows.transferMethods)"
        grantOp     = "$($g.operator)"
        grant       = (@($g.builtInControls) | Sort-Object) -join ','
        strength    = "$($g.authenticationStrength.id)"
        sif         = if ($s.signInFrequency.isEnabled) { "$($s.signInFrequency.frequencyInterval)/$($s.signInFrequency.value)$($s.signInFrequency.type)" } else { '' }
        browser     = if ($s.persistentBrowser.isEnabled) { "$($s.persistentBrowser.mode)" } else { '' }
    }
    if (-not $ignoreUsers) { $sig.inGroups = (@($c.users.includeGroups) | Sort-Object) -join ','; $sig.inUsers = (@($c.users.includeUsers) | Sort-Object) -join ',' }
    $sig
}

$existing = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identity/conditionalAccess/policies').value
$rows = @()
foreach ($file in Get-ChildItem (Join-Path $phase 'policies') -Filter 'CA*.json' | Sort-Object Name) {
    $num = $file.Name.Substring(0, 5)
    if ($Only -and $Only -notcontains $num) { continue }
    $json = Get-Content $file.FullName -Raw
    foreach ($k in $map.Keys) { $json = $json.Replace($k, $map[$k]) }
    $json = $json.Replace('"{{ADMIN_ALLOWED_APP_IDS}}"', $appIds)
    $policy = $json | ConvertFrom-Json -AsHashtable
    $ringManaged = $cfg.rollout.ringManagedPolicies -contains $num
    $live = $existing | Where-Object { $_.displayName -like "$num-*" } | Select-Object -First 1

    if (-not $live) {
        Invoke-MgGraphRequest -Method POST -Uri 'v1.0/identity/conditionalAccess/policies' -Body ($policy | ConvertTo-Json -Depth 20) -ContentType 'application/json' | Out-Null
        $rows += [pscustomobject]@{ Policy = $policy.displayName; Result = 'Created (report-only)' }; continue
    }
    $want = Get-Signature ($policy | ConvertTo-Json -Depth 20 | ConvertFrom-Json) $ringManaged
    $have = Get-Signature $live $ringManaged
    $diff = @($want.Keys | Where-Object { $want[$_] -ne $have[$_] } | ForEach-Object { "$_ is '$($have[$_])', expected '$($want[$_])'" })
    if ($live.displayName -ne $policy.displayName) { $diff += "name is '$($live.displayName)'" }
    if (-not $diff) { $rows += [pscustomobject]@{ Policy = $live.displayName; Result = "Exists, matches definition [$($live.state)]" }; continue }
    if ($UpdateExisting) {
        $policy.state = $live.state                                  # never change enforcement here
        if ($ringManaged) { $policy.conditions.users.includeUsers = @($live.conditions.users.includeUsers); $policy.conditions.users.includeGroups = @($live.conditions.users.includeGroups) }
        Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/identity/conditionalAccess/policies/$($live.id)" -Body ($policy | ConvertTo-Json -Depth 20) -ContentType 'application/json' | Out-Null
        $rows += [pscustomobject]@{ Policy = $policy.displayName; Result = "UPDATED [$($live.state)]: $($diff -join '; ')" }
    } else {
        $rows += [pscustomobject]@{ Policy = $live.displayName; Result = "DIFFERS: $($diff -join '; ')" }
    }
}
$rows | Format-Table -AutoSize -Wrap
if ($rows | Where-Object Result -like 'DIFFERS*') { Write-Host 'Fix in the portal, or rerun with -UpdateExisting (optionally -Only CA100).' -ForegroundColor Yellow }
