#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Control test for every federated application. Run weekly; exit code 1 on any finding.

.DESCRIPTION
      FA-01 Enterprise app exists and "Assignment required" is on
      FA-02 Business owner set as an owner of the enterprise app (who reviews access in Phase 13)
      FA-03 SAML signing certificate valid for more than 30 days (an expired cert = nobody can sign in)
      FA-04 Client secrets: none valid for more than 31 days, and listed for Phase 10 to remove
      FA-05 Provisioning jobs running, not in quarantine, last cycle without escrows/failures
      FA-06 No users assigned directly: access is granted through groups only (policy AC-01)
#>
$ErrorActionPreference = 'Stop'
$phase  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$design = Get-Content (Join-Path $phase 'config\federation-design.json') -Raw -Encoding utf8 | ConvertFrom-Json
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Application.Read.All', 'Synchronization.Read.All', 'User.Read.All'

$f = [System.Collections.Generic.List[object]]::new()
function Add($app, $id, $msg) { $f.Add([pscustomobject]@{ App = $app; Check = $id; Finding = $msg }) }
$now = Get-Date
foreach ($a in $design.apps | Where-Object type -ne 'designOnly') {
    $sp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=displayName eq '$($a.displayName)'").value | Select-Object -First 1
    if (-not $sp) { Add $a.key 'FA-01' 'enterprise app not found'; continue }
    if ($a.labAssignments -and -not $sp.appRoleAssignmentRequired) { Add $a.key 'FA-01' 'Assignment required is off' }

    $owners = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($sp.id)/owners?`$select=displayName").value.displayName
    if ($owners -notcontains $a.businessOwner) { Add $a.key 'FA-02' "business owner $($a.businessOwner) isn't an owner" }

    foreach ($k in $sp.keyCredentials | Where-Object usage -eq 'Verify') {
        $days = ([datetime]$k.endDateTime - $now).TotalDays
        if ($days -lt 30) { Add $a.key 'FA-03' ("SAML signing certificate expires in {0:N0} days" -f $days) }
    }
    $appReg = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/applications?`$filter=appId eq '$($sp.appId)'&`$select=passwordCredentials").value | Select-Object -First 1
    foreach ($p in $appReg.passwordCredentials) {
        $life = ([datetime]$p.endDateTime - [datetime]$p.startDateTime).TotalDays
        if ($life -gt 31) { Add $a.key 'FA-04' ("client secret '{0}' lives {1:N0} days (max 31 until Phase 10 removes it)" -f $p.displayName, $life) }
        else { Write-Host ("  note  {0}: client secret expires {1:yyyy-MM-dd} (Phase 10 replaces it)" -f $a.key, [datetime]$p.endDateTime) -ForegroundColor DarkGray }
    }
    if ($a.provisioning) {
        $job = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($sp.id)/synchronization/jobs").value | Select-Object -First 1
        if (-not $job) { Add $a.key 'FA-05' 'provisioning not configured' }
        else {
            if ($job.status.code -ne 'Active') { Add $a.key 'FA-05' "provisioning status $($job.status.code)" }
            if ($job.status.quarantine) { Add $a.key 'FA-05' "QUARANTINED: $($job.status.quarantine.reason)" }
            $last = $job.status.lastExecution
            if ($last -and $last.countEscrowed -gt 0) { Add $a.key 'FA-05' "last cycle had $($last.countEscrowed) escrowed (failing) objects" }
        }
    }
    $direct = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo?`$top=999").value | Where-Object principalType -eq 'User'
    foreach ($d in $direct) { Add $a.key 'FA-06' "user $($d.principalDisplayName) assigned directly" }
}
$f | Export-Csv (Join-Path $phase ("evidence\{0}-federated-apps-test.csv" -f (Get-Date -Format 'yyyyMMdd'))) -NoTypeInformation -Encoding utf8
if ($f.Count) { $f | Format-Table -AutoSize -Wrap; exit 1 }
Write-Host 'PASS: every federated app is group-assigned, owned, within certificate and secret limits, and provisioning healthy.' -ForegroundColor Green
