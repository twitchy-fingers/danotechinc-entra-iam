#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Exports what every Lifecycle Workflow did, per user and per task, as audit evidence.

.DESCRIPTION
    Auditors don't accept "the workflow is configured". They want proof it ran for the right
    people at the right time. This exports, for each workflow: every user it processed, when,
    and the outcome of each task, to evidence\YYYYMMDD-jml-workflow-results.csv.
#>
param([datetime] $Since = (Get-Date).AddDays(-30))
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'LifecycleWorkflows.Read.All', 'User.Read.All'

$rows = @()
$wfs = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identityGovernance/lifecycleWorkflows/workflows?$select=id,displayName').value
foreach ($wf in $wfs) {
    $uri = "v1.0/identityGovernance/lifecycleWorkflows/workflows/$($wf.id)/userProcessingResults?`$expand=subject,taskProcessingResults"
    while ($uri) {
        $p = Invoke-MgGraphRequest -Method GET -Uri $uri
        foreach ($r in $p.value) {
            if ([datetime]$r.startedDateTime -lt $Since) { continue }
            $user = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/$($r.subject.id)?`$select=displayName,employeeId" -ErrorAction SilentlyContinue
            foreach ($t in $r.taskProcessingResults) {
                $rows += [pscustomobject]@{
                    Workflow = $wf.displayName; User = $user.displayName ?? $r.subject.id; EmployeeId = $user.employeeId
                    Started = $r.startedDateTime; ProcessingType = $r.workflowExecutionType
                    Task = $t.task.displayName ?? $t.id; TaskStatus = $t.processingStatus; Overall = $r.processingStatus
                }
            }
        }
        $uri = $p.'@odata.nextLink'
    }
}
$file = Join-Path $phase ("evidence\{0}-jml-workflow-results.csv" -f (Get-Date -Format 'yyyyMMdd'))
$rows | Sort-Object Started | Export-Csv $file -NoTypeInformation -Encoding utf8
$rows | Sort-Object Started | Format-Table Workflow, User, Task, TaskStatus, Started -AutoSize
Write-Host "Evidence written: $file" -ForegroundColor Cyan
