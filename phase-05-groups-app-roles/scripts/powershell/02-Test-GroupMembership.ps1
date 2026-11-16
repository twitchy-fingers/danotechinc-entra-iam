#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Proves every dynamic group contains exactly the people the RBAC model says it should.

.DESCRIPTION
    1. Re-runs the Phase 03 simulation against TODAY's HR snapshot (from Phase 04), so expected
       membership reflects joiners, movers and leavers since the model was designed.
    2. Reads every group's actual members from Entra ID.
    3. Compares them person by person: missing members, unexpected members.

    A difference means one of three things is wrong: the HR data, the provisioning mapping,
    or the rule. This is the test that ties Phases 02, 03, 04 and 05 together.
    Exit code 1 if any group differs.
#>
param([datetime] $AsOf = (Get-Date).Date)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$repo  = Resolve-Path (Join-Path $phase '..')
$snapshot = Join-Path $repo ("phase-04-jml-lifecycle\output\hr-snapshot-{0}.csv" -f $AsOf.ToString('yyyyMMdd'))
if (-not (Test-Path $snapshot)) { throw "No HR snapshot for $($AsOf.ToString('yyyy-MM-dd')). Run the Phase 04 feed for that date first." }

$simOut = Join-Path $env:TEMP 'danotech-sim05'
python (Join-Path $repo 'phase-03-rbac-design\scripts\python\build_access_model.py') --feed $snapshot --as-of $AsOf.ToString('yyyy-MM-dd') --out $simOut | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'Note: the simulation reported policy findings for this snapshot; comparing membership anyway.' -ForegroundColor Yellow }

$expected = @{}
foreach ($row in Import-Csv (Join-Path $simOut 'role-membership.csv') -Encoding utf8) {
    if ($row.EmploymentStatus -ne 'Active') { continue }      # disabled accounts never match a dynamic rule
    foreach ($rid in ($row.Roles -split ';' | Where-Object { $_ })) {
        if (-not $expected[$rid]) { $expected[$rid] = [System.Collections.Generic.HashSet[string]]::new() }
        [void]$expected[$rid].Add($row.EmployeeId)
    }
}

. (Join-Path $repo 'scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Group.Read.All', 'User.Read.All'
$roles = Get-Content (Join-Path $repo 'phase-03-rbac-design\generated\dynamic-group-rules.json') -Raw -Encoding utf8 |
    ConvertFrom-Json | Where-Object membershipType -eq 'Dynamic'

$results = @(); $bad = 0
foreach ($r in $roles) {
    $g = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$($r.groupName)'&`$select=id,membershipRuleProcessingState").value | Select-Object -First 1
    if (-not $g) { $results += [pscustomobject]@{ Group = $r.groupName; Expected = '-'; Actual = '-'; Missing = 'GROUP NOT FOUND'; Unexpected = '' }; $bad++; continue }
    $actual = [System.Collections.Generic.HashSet[string]]::new()
    $uri = "v1.0/groups/$($g.id)/members/microsoft.graph.user?`$select=employeeId&`$top=999"
    while ($uri) { $p = Invoke-MgGraphRequest -Method GET -Uri $uri; foreach ($m in $p.value) { [void]$actual.Add($m.employeeId) }; $uri = $p.'@odata.nextLink' }
    $exp = $expected[$r.roleId] ?? [System.Collections.Generic.HashSet[string]]::new()
    $missing    = @($exp | Where-Object { -not $actual.Contains($_) })
    $unexpected = @($actual | Where-Object { -not $exp.Contains($_) })
    if ($missing -or $unexpected) { $bad++ }
    $results += [pscustomobject]@{ Group = $r.groupName; Expected = $exp.Count; Actual = $actual.Count
        Missing = ($missing -join ','); Unexpected = ($unexpected -join ',') }
}
$results | Format-Table Group, Expected, Actual, Missing, Unexpected -AutoSize
$stamp = $AsOf.ToString('yyyyMMdd')
$results | Export-Csv (Join-Path $phase "evidence\$stamp-group-membership-test.csv") -NoTypeInformation -Encoding utf8
if ($bad) {
    Write-Host "$bad group(s) differ from the model. If the groups were created recently, dynamic processing may still be running: retry in 30 minutes." -ForegroundColor Yellow
    exit 1
}
Write-Host "All $($roles.Count) groups match the RBAC model exactly." -ForegroundColor Green
