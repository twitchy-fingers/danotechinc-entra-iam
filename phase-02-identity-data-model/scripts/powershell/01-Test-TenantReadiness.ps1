#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Checks whether the tenant is ready to receive the HR feed. Read-only.

.DESCRIPTION
    Before Phase 04 provisions 200 people, this script answers four questions:

    1. MATCH   Which feed records already have an account (same employeeId)?
               These will be adopted, not duplicated. Expected: Daniel Opara (DT01001).
    2. CLASH   Does any existing account hold a feed UPN but a different (or no)
               employeeId? Provisioning would fail or, worse, merge two people.
    3. ORPHAN  Which existing accounts have no employeeId and aren't documented
               exceptions (break-glass, adm. accounts)? They sit outside HR control.
    4. ATTRIB  Are extensionAttribute1-4 already used by anything? The data model
               reserves them for JobCode, JobLevel, JobFamily and IsPeopleManager.

    Runs as a human (delegated, User.Read.All) or as the automation app (-AppOnly).

.EXAMPLE
    ./01-Test-TenantReadiness.ps1
    ./01-Test-TenantReadiness.ps1 -AppOnly
#>
param(
    [string] $FeedPath       = (Join-Path $PSScriptRoot '..\..\..\data\hr\employees.csv'),
    [string] $EvidenceFolder = (Join-Path $PSScriptRoot '..\..\evidence'),
    [switch] $AppOnly
)

. (Join-Path $PSScriptRoot '..\..\..\scripts\common\Connect-Danotech.ps1')
if ($AppOnly) { Connect-Danotech -AppOnly } else { Connect-Danotech -Scopes 'User.Read.All' }

$feed = Import-Csv -Path $FeedPath -Encoding utf8
Write-Host "Feed: $($feed.Count) records" -ForegroundColor Cyan

# --- Pull every user once ---------------------------------------------------
$uri = 'v1.0/users?$select=id,userPrincipalName,displayName,employeeId,employeeType,accountEnabled,onPremisesExtensionAttributes&$top=999'
$users = @()
while ($uri) {
    $page = Invoke-MgGraphRequest -Method GET -Uri $uri
    $users += $page.value
    $uri = $page.'@odata.nextLink'
}
Write-Host "Tenant: $($users.Count) users" -ForegroundColor Cyan

$byEmpId = @{}; $byUpn = @{}
foreach ($u in $users) {
    if ($u.employeeId) { $byEmpId[$u.employeeId] = $u }
    $byUpn[$u.userPrincipalName.ToLower()] = $u
}

$results = [ordered]@{ match = @(); clash = @(); orphan = @(); attributeInUse = @() }

# --- 1 & 2: feed vs tenant --------------------------------------------------
foreach ($r in $feed) {
    $existing = $byEmpId[$r.EmployeeId]
    $upnOwner = $byUpn[$r.UserPrincipalName.ToLower()]

    if ($existing -and $existing.employeeType -ne 'AdminAccount') {
        $results.match += [pscustomobject]@{
            EmployeeId = $r.EmployeeId; FeedUPN = $r.UserPrincipalName; TenantUPN = $existing.userPrincipalName
            Note = if ($existing.userPrincipalName -ieq $r.UserPrincipalName) { 'Will be adopted' } else { 'Adopted; UPN will be updated' }
        }
    }
    if ($upnOwner -and $upnOwner.employeeId -ne $r.EmployeeId) {
        $results.clash += [pscustomobject]@{
            EmployeeId = $r.EmployeeId; UPN = $r.UserPrincipalName
            ExistingEmployeeId = ($upnOwner.employeeId ?? '<none>'); ExistingDisplayName = $upnOwner.displayName
        }
    }
}

# --- 3: accounts outside HR control -----------------------------------------
$feedIds = [System.Collections.Generic.HashSet[string]]::new([string[]]$feed.EmployeeId)
foreach ($u in $users) {
    $isBreakGlass = $u.userPrincipalName -like 'bg-*'
    $isAdmin      = $u.employeeType -eq 'AdminAccount'
    if ($isBreakGlass) { continue }                                  # documented exception (Phase 01)
    if ($isAdmin -and $u.employeeId -and $feedIds.Contains($u.employeeId)) { continue }   # adm. account linked to a real person
    if (-not $u.employeeId -or -not $feedIds.Contains($u.employeeId)) {
        $results.orphan += [pscustomobject]@{
            UPN = $u.userPrincipalName; EmployeeId = ($u.employeeId ?? '<none>'); Enabled = $u.accountEnabled
            Reason = if ($isAdmin) { 'Admin account not linked to an employee in the feed' } else { 'No matching HR record' }
        }
    }
}

# --- 4: reserved extension attributes ---------------------------------------
foreach ($u in $users) {
    $ext = $u.onPremisesExtensionAttributes
    foreach ($n in 1..4) {
        $v = $ext."extensionAttribute$n"
        if ($v) { $results.attributeInUse += [pscustomobject]@{ UPN = $u.userPrincipalName; Attribute = "extensionAttribute$n"; Value = $v } }
    }
}

# --- Report -----------------------------------------------------------------
Write-Host "`n1. Feed records that already have an account (will be adopted): $($results.match.Count)" -ForegroundColor Green
$results.match | Format-Table -AutoSize

$c = if ($results.clash.Count) { 'Red' } else { 'Green' }
Write-Host "2. UPN clashes (must be resolved before Phase 04): $($results.clash.Count)" -ForegroundColor $c
$results.clash | Format-Table -AutoSize

$c = if ($results.orphan.Count) { 'Yellow' } else { 'Green' }
Write-Host "3. Accounts outside HR control: $($results.orphan.Count)" -ForegroundColor $c
$results.orphan | Format-Table -AutoSize

$c = if ($results.attributeInUse.Count) { 'Yellow' } else { 'Green' }
Write-Host "4. Reserved extension attributes already in use: $($results.attributeInUse.Count)" -ForegroundColor $c
$results.attributeInUse | Format-Table -AutoSize

$ready = ($results.clash.Count -eq 0)
Write-Host ("Tenant ready for HR provisioning: {0}" -f ($ready ? 'YES' : 'NO - resolve clashes first')) -ForegroundColor ($ready ? 'Green' : 'Red')

$stamp = Get-Date -Format 'yyyyMMdd'
$file = Join-Path $EvidenceFolder "$stamp-tenant-readiness.json"
[ordered]@{ capturedAt = (Get-Date).ToUniversalTime().ToString('o'); feedRecords = $feed.Count; tenantUsers = $users.Count
            ready = $ready; results = $results } | ConvertTo-Json -Depth 6 | Set-Content $file -Encoding utf8
Write-Host "Evidence written to $file" -ForegroundColor Cyan
