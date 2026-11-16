#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Runs one HR feed cycle: snapshot -> quality gate -> SCIM transform -> upload.

.DESCRIPTION
    1. SNAPSHOT  build_hr_snapshot.py produces today's HR export (master file + dated HR changes).
    2. GATE      The Phase 02 validator checks it, including the mass-change guard against the
                 previous snapshot. Any ERROR stops the run here. Nothing reaches Entra ID.
    3. TRANSFORM Each record becomes a SCIM user. IAM derives two attributes (contract v1.0):
                   active           = Status is Active and the end date hasn't passed
                   PeopleManager    = 'PeopleManager' if anyone reports to them, else 'IndividualContributor'
                 A Terminated record is sent ONLY if an account with that employeeId already exists,
                 so it gets disabled. If there's no account, there's nothing to disable, and sending
                 it would CREATE a disabled account for someone who left. That one rule covers:
                   - people who left before the first load (Sofía Reyes)
                   - leavers WF-05 has already deleted (no resurrection)
    4. UPLOAD    Up to 50 records per /bulkUpload request (API limit), managers before their reports,
                 so manager references resolve on the first pass.

    Run manually now; Phase 04 ends with a note on scheduling it later.

.PARAMETER AsOf         The HR "today". Defaults to today. Use the schedule dates (e.g. 2026-11-09).
.PARAMETER DryRun       Build and save the SCIM payloads under output\scim-<date>\ but don't upload.
                        Without automation credentials, assumes no accounts exist yet (first load).
.PARAMETER Interactive  Sign in as an admin instead of using the automation app.

.EXAMPLE
    ./03-Invoke-HrFeedUpload.ps1 -AsOf 2026-11-07 -DryRun
    ./03-Invoke-HrFeedUpload.ps1 -AsOf 2026-11-07
    ./03-Invoke-HrFeedUpload.ps1 -AsOf 2026-11-09
#>
[CmdletBinding()]
param(
    [datetime] $AsOf = (Get-Date).Date,
    [switch]   $DryRun,
    [switch]   $Interactive
)

$ErrorActionPreference = 'Stop'
$phase   = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$repo    = Resolve-Path (Join-Path $phase '..')
$outDir  = Join-Path $phase 'output'
$stamp   = $AsOf.ToString('yyyyMMdd')
$today   = $AsOf.Date
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# ---------------------------------------------------------------- 1. Snapshot
Write-Host "`n[1/4] Building HR snapshot as of $($today.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
$snapshot = Join-Path $outDir "hr-snapshot-$stamp.csv"
python (Join-Path $phase 'scripts\python\build_hr_snapshot.py') --as-of $today.ToString('yyyy-MM-dd') --out $snapshot
if ($LASTEXITCODE -ne 0) { throw 'Snapshot build failed.' }

# ---------------------------------------------------------------- 2. Quality gate
Write-Host "`n[2/4] Running the Phase 02 quality gate" -ForegroundColor Cyan
$previous = Get-ChildItem $outDir -Filter 'hr-snapshot-*.csv' |
    Where-Object { $_.BaseName -lt "hr-snapshot-$stamp" } | Sort-Object Name | Select-Object -Last 1
$validator = Join-Path $repo 'phase-02-identity-data-model\scripts\python\validate_hr_feed.py'
$report    = Join-Path $outDir "validation-$stamp.md"
$gateArgs  = @($validator, $snapshot, '--as-of', $today.ToString('yyyy-MM-dd'), '--report', $report)
if ($previous) { $gateArgs += @('--previous', $previous.FullName); Write-Host "  Mass-change guard compares with $($previous.Name)" }
$gateOutput = python @gateArgs
$gateExit = $LASTEXITCODE          # capture before anything else runs
$gateOutput | Select-Object -First 8 | ForEach-Object { Write-Host "  $_" }
if ($gateExit -ne 0) {
    throw "Quality gate BLOCKED the feed. See $report. Fix the HR data; nothing was sent to Entra ID."
}

# ---------------------------------------------------------------- 3. Transform
Write-Host "`n[3/4] Transforming records to SCIM" -ForegroundColor Cyan

# Which employeeIds already have an account? (Decides whether Terminated records are sent.)
. (Join-Path $repo 'scripts\common\Connect-Danotech.ps1')
$existingIds = [System.Collections.Generic.HashSet[string]]::new()
$canConnect = $Interactive -or ($env:DANOTECH_AUTOMATION_CLIENT_ID -and $env:DANOTECH_AUTOMATION_CERT_THUMBPRINT)
if ($canConnect) {
    if ($Interactive) { Connect-Danotech -Scopes 'SynchronizationData-User.Upload', 'User.Read.All' } else { Connect-Danotech -AppOnly }
    $uri = 'v1.0/users?$select=employeeId,employeeType&$top=999'
    while ($uri) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $uri
        foreach ($u in $page.value) { if ($u.employeeId -and $u.employeeType -ne 'AdminAccount') { [void]$existingIds.Add($u.employeeId) } }
        $uri = $page.'@odata.nextLink'
    }
    Write-Host "  $($existingIds.Count) HR-linked accounts already exist in Entra ID"
} elseif ($DryRun) {
    Write-Host '  No automation credentials: dry run assumes no accounts exist yet (first load).' -ForegroundColor Yellow
} else { throw 'Set the automation app environment variables (Phase 01 Step 10) or use -Interactive.' }
$rows = Import-Csv $snapshot -Encoding utf8
$byId = @{}; foreach ($r in $rows) { $byId[$r.EmployeeId] = $r }
$managers = [System.Collections.Generic.HashSet[string]]::new()
foreach ($r in $rows) { if ($r.ManagerEmployeeId) { [void]$managers.Add($r.ManagerEmployeeId) } }

function Get-Depth($r) {
    $d = 0; $cur = $r
    while ($cur.ManagerEmployeeId -and $byId.ContainsKey($cur.ManagerEmployeeId) -and $d -lt 20) { $d++; $cur = $byId[$cur.ManagerEmployeeId] }
    $d
}
function ConvertTo-Date([string] $s) { if ($s) { [datetime]::ParseExact($s, 'yyyy-MM-dd', $null) } else { $null } }

$schemaCore = 'urn:ietf:params:scim:schemas:core:2.0:User'
$schemaEnt  = 'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'
$schemaDt   = 'urn:ietf:params:scim:schemas:extension:danotech:1.0:User'

$ops = @(); $skipped = @(); $stats = @{ active = 0; inactive = 0 }
foreach ($r in ($rows | Sort-Object { Get-Depth $_ }, EmployeeId)) {
    $end = ConvertTo-Date $r.EndDate
    if ($r.EmploymentStatus -eq 'Terminated' -and -not $existingIds.Contains($r.EmployeeId)) {
        $skipped += "$($r.EmployeeId) $($r.DisplayName): terminated and has no account (never created, or already deleted)"; continue
    }

    $active = ($r.EmploymentStatus -eq 'Active') -and (-not $end -or $end -ge $today)
    if ($active) { $stats.active++ } else { $stats.inactive++ }

    $enterprise = [ordered]@{
        employeeNumber = $r.EmployeeId
        department     = $r.Department
        costCenter     = $r.CostCenter
        division       = $r.Division
        organization   = $r.CompanyName
    }
    if ($r.ManagerEmployeeId) { $enterprise.manager = @{ value = $r.ManagerEmployeeId } }

    $danotech = [ordered]@{
        JobCode       = $r.JobCode
        JobLevel      = $r.JobLevel
        JobFamily     = $r.JobFamily
        PeopleManager = if ($managers.Contains($r.EmployeeId)) { 'PeopleManager' } else { 'IndividualContributor' }
        EmployeeType  = $r.EmployeeType
        UsageLocation = $r.UsageLocation
        Office        = $r.Office
        MailNickname  = $r.MailNickname
        HireDate      = (ConvertTo-Date $r.HireDate).ToString('yyyy-MM-ddT08:00:00Z')
    }
    if ($end) { $danotech.LeaveDate = $end.ToString('yyyy-MM-ddT23:59:59Z') }

    $ops += [ordered]@{
        method = 'POST'
        bulkId = [guid]::NewGuid().ToString()
        path   = '/Users'
        data   = [ordered]@{
            schemas     = @($schemaCore, $schemaEnt, $schemaDt)
            externalId  = $r.EmployeeId
            userName    = $r.UserPrincipalName
            active      = $active
            displayName = $r.DisplayName
            name        = @{ givenName = $r.FirstName; familyName = $r.LastName }
            title       = $r.JobTitle
            addresses   = @(@{ type = 'work'; locality = $r.City; country = $r.Country })
            $schemaEnt  = $enterprise
            $schemaDt   = $danotech
        }
    }
}
Write-Host ("  {0} records to send ({1} active, {2} inactive), {3} skipped" -f $ops.Count, $stats.active, $stats.inactive, $skipped.Count)
$skipped | ForEach-Object { Write-Host "    skip: $_" -ForegroundColor DarkGray }

# ---------------------------------------------------------------- 4. Upload
$batches = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $ops.Count; $i += 50) { $batches.Add($ops[$i..([math]::Min($i + 49, $ops.Count - 1))]) }

if ($DryRun) {
    $scimDir = Join-Path $outDir "scim-$stamp"
    New-Item -ItemType Directory -Path $scimDir -Force | Out-Null
    $n = 0
    foreach ($b in $batches) {
        $n++
        @{ schemas = @('urn:ietf:params:scim:api:messages:2.0:BulkRequest'); Operations = @($b) } |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $scimDir ("batch-{0:d2}.json" -f $n)) -Encoding utf8
    }
    Write-Host "`n[4/4] DRY RUN: $n batch file(s) written to $scimDir. Nothing uploaded." -ForegroundColor Yellow
    return
}

$targetFile = Join-Path $phase 'config\provisioning-target.local.json'
if (-not (Test-Path $targetFile)) { throw "Missing $targetFile. Run 01-Save-ProvisioningTarget.ps1 first (walkthrough Step 5)." }
$target = Get-Content $targetFile -Raw | ConvertFrom-Json

Write-Host "`n[4/4] Uploading $($batches.Count) batch(es) to the provisioning job" -ForegroundColor Cyan
$uri = "v1.0/servicePrincipals/$($target.servicePrincipalId)/synchronization/jobs/$($target.jobId)/bulkUpload"
$started = (Get-Date).ToUniversalTime()
$n = 0
foreach ($b in $batches) {
    $n++
    $body = @{ schemas = @('urn:ietf:params:scim:api:messages:2.0:BulkRequest'); Operations = @($b) } | ConvertTo-Json -Depth 10 -Compress
    Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/scim+json' | Out-Null
    Write-Host "  Batch $n/$($batches.Count): $(@($b).Count) records accepted (HTTP 202)" -ForegroundColor Green
}

[ordered]@{
    asOf = $today.ToString('yyyy-MM-dd'); uploadStartedUtc = $started.ToString('o')
    recordsSent = $ops.Count; active = $stats.active; inactive = $stats.inactive; skipped = $skipped; batches = $batches.Count
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outDir "upload-$stamp.json") -Encoding utf8

Write-Host "`nAccepted. The provisioning service processes asynchronously: allow 5-10 minutes," -ForegroundColor Cyan
Write-Host "then run: ./04-Get-ProvisioningResults.ps1 -Since '$($started.ToString('o'))'" -ForegroundColor Cyan
