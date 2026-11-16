#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Saves the provisioning app's API endpoint for the upload script, and checks it works.

.DESCRIPTION
    After creating the API-driven provisioning app in the portal (walkthrough Step 2), its
    Overview page shows the "Provisioning API Endpoint", for example:
      https://graph.microsoft.com/v1.0/servicePrincipals/<spId>/synchronization/jobs/<jobId>/bulkUpload
    Paste it here. The script extracts the service principal and job IDs, confirms the job
    exists and is running, and saves them to config\provisioning-target.local.json (git-ignored).
.EXAMPLE
    ./01-Save-ProvisioningTarget.ps1 -Endpoint 'https://graph.microsoft.com/v1.0/servicePrincipals/.../bulkUpload'
#>
param([Parameter(Mandatory)] [string] $Endpoint)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
if ($Endpoint -notmatch 'servicePrincipals/([0-9a-f-]{36})/synchronization/jobs/([^/]+)/bulkUpload') {
    throw 'That doesn''t look like a provisioning API endpoint. Copy it from the app''s Overview page.'
}
$spId, $jobId = $Matches[1], $Matches[2]

. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Synchronization.Read.All'
$job = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$spId/synchronization/jobs/$jobId"
$sp  = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($spId)?`$select=displayName"
Write-Host "Provisioning app: $($sp.displayName)" -ForegroundColor Green
Write-Host "Job status: $($job.status.code)" -ForegroundColor ($job.status.code -eq 'Active' ? 'Green' : 'Yellow')
if ($job.status.code -ne 'Active') { Write-Host 'Turn Provisioning Status On in the portal (walkthrough Step 4).' -ForegroundColor Yellow }

[ordered]@{ servicePrincipalId = $spId; jobId = $jobId; appName = $sp.displayName } | ConvertTo-Json |
    Set-Content (Join-Path $phase 'config\provisioning-target.local.json') -Encoding utf8
Write-Host 'Saved to config\provisioning-target.local.json' -ForegroundColor Cyan
