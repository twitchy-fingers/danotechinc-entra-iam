#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Exports Phase 08 evidence: sign-ins per federated app (with protocol), provisioning activity
    for Salesforce and GitHub, and each app's federation configuration.
#>
param([int] $Days = 14)
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\federation-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Application.Read.All', 'AuditLog.Read.All'
$stamp = Get-Date -Format 'yyyyMMdd'; $ev = Join-Path $phase 'evidence'
$since = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

$signins = @(); $prov = @(); $config = @()
foreach ($a in $design.apps | Where-Object type -ne 'designOnly') {
    $sp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=displayName eq '$($a.displayName)'").value | Select-Object -First 1
    if (-not $sp) { continue }
    $config += [pscustomobject]@{ App = $a.displayName; Protocols = ($a.protocols -join '; '); SsoMode = $sp.preferredSingleSignOnMode
        AssignmentRequired = $sp.appRoleAssignmentRequired; AppRoles = (($sp.appRoles | ForEach-Object { $_.value ?? $_.displayName }) -join ', ')
        SamlCertExpires = (($sp.keyCredentials | Where-Object usage -eq 'Verify').endDateTime | Sort-Object | Select-Object -Last 1) }
    $signins += (Invoke-MgGraphRequest -Method GET -Uri "v1.0/auditLogs/signIns?`$filter=appId eq '$($sp.appId)' and createdDateTime ge $since&`$top=200").value |
        ForEach-Object { [pscustomobject]@{ Time = $_.createdDateTime; App = $a.displayName; User = $_.userPrincipalName; Protocol = $_.authenticationProtocol
            Result = $_.status.errorCode; Reason = $_.status.failureReason; CA = $_.conditionalAccessStatus } }
    if ($a.provisioning) {
        $prov += (Invoke-MgGraphRequest -Method GET -Uri "v1.0/auditLogs/provisioning?`$filter=activityDateTime ge $since&`$top=500").value |
            Where-Object { $_.servicePrincipal.id -eq $sp.id } |
            ForEach-Object { [pscustomobject]@{ Time = $_.activityDateTime; App = $a.displayName; User = $_.sourceIdentity.displayName
                Action = $_.provisioningAction; Status = $_.provisioningStatusInfo.status; Reason = $_.provisioningStatusInfo.errorInformation.reason } }
    }
}
$config  | Export-Csv (Join-Path $ev "$stamp-federated-apps.csv") -NoTypeInformation -Encoding utf8
$signins | Export-Csv (Join-Path $ev "$stamp-federated-signins.csv") -NoTypeInformation -Encoding utf8
$prov    | Export-Csv (Join-Path $ev "$stamp-outbound-provisioning.csv") -NoTypeInformation -Encoding utf8
$config | Format-Table App, SsoMode, AssignmentRequired, AppRoles -AutoSize
Write-Host "Evidence written to $ev ($($signins.Count) sign-ins, $($prov.Count) provisioning events)" -ForegroundColor Green
