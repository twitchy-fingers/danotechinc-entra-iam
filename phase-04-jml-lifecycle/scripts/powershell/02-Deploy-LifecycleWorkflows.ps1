#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Creates the remaining joiner, mover and leaver workflows from config\workflows\*.json,
    and checks any workflow you built in the portal against its definition.

.DESCRIPTION
    WF-02 is built by hand in the portal (walkthrough Step 6a), to learn the interface.
    This script creates the other four, and for any workflow that already exists it COMPARES
    the live configuration with the JSON (trigger, offset, scope, tasks) and reports differences.
    Manual work is verified, not trusted.

    Workflows are stored as code. Each task is named by its portal display name
    (e.g. "Disable user account"); this script looks up Microsoft's task definition
    ID at runtime, so a wrong hard-coded GUID can never break a deployment.

    TIMING MATTERS: a time-based workflow doesn't fire for users whose hire or leave
    date is earlier than the workflow's creation date. Deploy before the first joiner
    you want covered (Niamh Jones, 9 Nov 2026).

    Idempotent: workflows that already exist (same display name) are skipped.
    Run as adm.daniel.opara.
#>
param([string] $WorkflowFolder = (Join-Path $PSScriptRoot '..\..\config\workflows'))
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'LifecycleWorkflows.ReadWrite.All'

$defs = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identityGovernance/lifecycleWorkflows/taskDefinitions').value
$live = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identityGovernance/lifecycleWorkflows/workflows?$expand=tasks').value
$existing = $live | ForEach-Object { $_.displayName }

function Get-TriggerInfo($t) {
    # Normalises the older (timeBasedAttribute/offsetInDays) and newer
    # (attribute/operator.offsetInDays + eventTiming) trigger formats.
    if (-not $t) { return @{} }
    if ($t.attribute) {
        $offset = [int]$t.operator.offsetInDays
        if ($t.operator.eventTiming -eq 'before') { $offset = -$offset }
        return @{ attribute = $t.attribute; offset = $offset }
    }
    return @{ attribute = $t.timeBasedAttribute; offset = $t.offsetInDays }
}

function Compare-Workflow($wf, $liveWf) {
    $diffs = @()
        $t  = Get-TriggerInfo $wf.executionConditions.trigger
    $lt = Get-TriggerInfo $liveWf.executionConditions.trigger
    if ($t.attribute -and $t.attribute -ne $lt.attribute) { $diffs += "trigger attribute is '$($lt.attribute)', expected '$($t.attribute)'" }
    if ($null -ne $t.offset -and $t.offset -ne $lt.offset) { $diffs += "offset is $($lt.offset) days, expected $($t.offset)" }
    $rule, $lrule = $wf.executionConditions.scope.rule, $liveWf.executionConditions.scope.rule
    if (($rule -replace '\s', '') -ne ($lrule -replace '\s', '')) { $diffs += "scope is '$lrule', expected '$rule'" }
    $want = @($wf.tasks | ForEach-Object { (Resolve-Task $_.taskName).id })
    $have = @($liveWf.tasks | Where-Object isEnabled | ForEach-Object { $_.taskDefinitionId })
    foreach ($id in $want) { if ($have -notcontains $id) { $diffs += "missing task '$(($defs | Where-Object id -eq $id).displayName)'" } }
    foreach ($id in $have) { if ($want -notcontains $id) { $diffs += "unexpected task '$(($defs | Where-Object id -eq $id).displayName)'" } }
    foreach ($a in ($wf.tasks | ForEach-Object { $_.arguments } | Where-Object { $_ })) {
        $la = $liveWf.tasks.arguments | Where-Object name -eq $a.name | Select-Object -First 1
        if ($la -and "$($la.value)" -ne "$($a.value)") { $diffs += "task argument $($a.name) is '$($la.value)', expected '$($a.value)'" }
    }
    $diffs
}

function Resolve-Task([string] $name) {
    $exact = $defs | Where-Object { $_.displayName -eq $name }
    if ($exact) { return $exact | Select-Object -First 1 }
    $like = @($defs | Where-Object { $_.displayName -like "*$name*" })
    if ($like.Count -eq 1) { return $like[0] }
    Write-Host "Task '$name' not found. Available task names:" -ForegroundColor Red
    $defs | Sort-Object displayName | ForEach-Object { Write-Host "  - $($_.displayName)" }
    throw "Fix the taskName in the workflow JSON."
}

$created = @()
foreach ($file in Get-ChildItem $WorkflowFolder -Filter 'WF-*.json' | Sort-Object Name) {
    $wf = Get-Content $file.FullName -Raw | ConvertFrom-Json -AsHashtable
    if ($existing -contains $wf.displayName) {
        $liveId = ($live | Where-Object {$_.displayName -eq $wf.displayName} | Select-Object -First 1).id
        $liveWf = Invoke-MgGraphRequest -Method GET -Uri "v1.0/identityGovernance/lifecycleWorkflows/Workflows/$($liveId)?`$expand=tasks"
        $diffs = @(Compare-Workflow $wf $liveWf)
        if ($diffs) {
            Write-Host "Exists, DIFFERS from definition: $($wf.displayName)" -ForegroundColor Red
            $diffs | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            Write-Host '    Fix it in the portal (workflow > Properties / Tasks), then rerun this script.' -ForegroundColor Yellow
        } else { Write-Host "Exists, matches definition: $($wf.displayName)" -ForegroundColor Green }
        continue
    }

    $order = 0
    $wf.tasks = @(foreach ($t in $wf.tasks) {
        $def = Resolve-Task $t.taskName
        $order++
        [ordered]@{
            category          = $wf.category
            continueOnError   = $t.continueOnError
            description       = $def.description
            displayName       = $def.displayName
            executionSequence = $order
            isEnabled         = $t.isEnabled
            taskDefinitionId  = $def.id
            arguments         = @($t.arguments)
        }
    })
    $result = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/identityGovernance/lifecycleWorkflows/workflows' -Body $wf
    $created += $result.id
    Write-Host "Created: $($wf.displayName) ($($result.id))" -ForegroundColor Green
}

$stamp = Get-Date -Format 'yyyyMMdd'
Invoke-MgGraphRequest -Method GET -Uri 'v1.0/identityGovernance/lifecycleWorkflows/workflows?$expand=tasks' |
    ConvertTo-Json -Depth 20 | Set-Content (Join-Path $phase "evidence\$stamp-lifecycle-workflows.json") -Encoding utf8
Write-Host "Evidence written: evidence\$stamp-lifecycle-workflows.json" -ForegroundColor Cyan
