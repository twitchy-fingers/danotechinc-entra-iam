#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Exports a point-in-time snapshot of tenant security configuration.

.DESCRIPTION
    Why: you can't show improvement without a "before". This snapshot is the
    first piece of audit evidence in the program and is re-run at the end of
    the phase to prove what changed.

    Read-only. Uses Invoke-MgGraphRequest so every call maps 1:1 to a
    documented Graph REST endpoint (the same endpoints the Python scripts use).

.PARAMETER OutputFolder
    Where to write the JSON files. Defaults to the phase evidence folder.

.EXAMPLE
    ./01-Get-TenantBaseline.ps1 -Label before
#>
param(
    [string] $OutputFolder = (Join-Path $PSScriptRoot '..\..\evidence'),
    [ValidateSet('before', 'after')] [string] $Label = 'before'
)

. (Join-Path $PSScriptRoot '..\..\..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Organization.Read.All', 'Directory.Read.All', 'Policy.Read.All', 'RoleManagement.Read.Directory'

$stamp = Get-Date -Format 'yyyyMMdd'
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

function Get-All([string] $Uri) {
    # Follows @odata.nextLink so large collections are returned completely.
    $items = @()
    while ($Uri) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $Uri
        if ($page.ContainsKey('value')) { $items += $page.value } else { return $page }
        $Uri = $page.'@odata.nextLink'
    }
    return $items
}

$snapshot = [ordered]@{
    capturedAt            = (Get-Date).ToUniversalTime().ToString('o')
    organization          = Get-All 'v1.0/organization?$select=id,displayName,verifiedDomains,createdDateTime'
    subscribedSkus        = Get-All 'v1.0/subscribedSkus?$select=skuPartNumber,prepaidUnits,consumedUnits'
    directorySubscriptions= Get-All 'v1.0/directory/subscriptions'
    securityDefaults      = Get-All 'v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
    authorizationPolicy   = Get-All 'v1.0/policies/authorizationPolicy'
    conditionalAccess     = Get-All 'v1.0/identity/conditionalAccess/policies'
    roleAssignments       = Get-All 'v1.0/roleManagement/directory/roleAssignments?$expand=principal'
    roleDefinitions       = Get-All 'v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,templateId&$filter=isBuiltIn eq true'
}

# Human-readable summary of who holds which role. This is what an auditor asks for first.
$roleNames = @{}
$snapshot.roleDefinitions | ForEach-Object { $roleNames[$_.templateId] = $_.displayName }
$summary = $snapshot.roleAssignments | ForEach-Object {
    [pscustomobject]@{
        Role      = $roleNames[$_.roleDefinitionId]
        Principal = $_.principal.userPrincipalName ?? $_.principal.displayName
        Scope     = $_.directoryScopeId
    }
}

$file = Join-Path $OutputFolder "$stamp-tenant-baseline-$Label.json"
$snapshot | ConvertTo-Json -Depth 20 | Set-Content -Path $file -Encoding utf8

Write-Host "`nLicences" -ForegroundColor Cyan
$snapshot.directorySubscriptions | ForEach-Object {
    [pscustomobject]@{
        Sku       = $_.skuPartNumber
        Seats     = $_.totalLicenses
        IsTrial   = $_.isTrial
        Status    = $_.status
        NextDate  = $_.nextLifecycleDateTime
    }
} | Format-Table -AutoSize

Write-Host "Security defaults enabled: $($snapshot.securityDefaults.isEnabled)" -ForegroundColor Cyan
Write-Host "Conditional Access policies: $(@($snapshot.conditionalAccess).Count)" -ForegroundColor Cyan
Write-Host "`nDirectory role assignments" -ForegroundColor Cyan
$summary | Sort-Object Role | Format-Table -AutoSize
Write-Host "Snapshot written to $file" -ForegroundColor Green
Write-Host "Review it before committing: it contains object IDs but no secrets." -ForegroundColor Yellow
