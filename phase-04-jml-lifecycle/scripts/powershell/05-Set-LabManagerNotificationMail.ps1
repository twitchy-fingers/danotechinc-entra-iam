#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    LAB ONLY: points every people manager's mail attribute at one external inbox you own.

.DESCRIPTION
    Lifecycle Workflows email the joiner's TAP (and onboarding, mover and leaver notices) to the
    MANAGER's `mail` attribute. DanotechInc has no mailboxes (ADR-0001), so this script sets each
    manager's mail to a plus-address of your inbox:
        you@outlook.com  ->  you+brandon.collins@outlook.com
    Every notification lands in one inbox, and the "+name" part tells you which manager it was for.
    Gmail and Outlook.com both deliver plus-addresses.

    The HR feed doesn't map `mail`, so provisioning never overwrites these values.
    If Entra ID rejects the external address, the script stops after the first attempt and tells
    you to use the fallback: issue the joiner's TAP in the portal (walkthrough Step 8).

    Run after the initial load (managers must exist). Run as adm.daniel.opara.
.EXAMPLE
    ./05-Set-LabManagerNotificationMail.ps1 -Inbox you@outlook.com -AsOf 2026-11-07
#>
param(
    [Parameter(Mandatory)] [ValidatePattern('^[^@+\s]+@[^@\s]+\.[^@\s]+$')] [string] $Inbox,
    [datetime] $AsOf = (Get-Date).Date
)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'User.ReadWrite.All'

$hr = Import-Csv (Join-Path $phase ("output\hr-snapshot-{0}.csv" -f $AsOf.ToString('yyyyMMdd'))) -Encoding utf8
$mgrIds = $hr.ManagerEmployeeId | Where-Object { $_ } | Sort-Object -Unique
$local, $domain = $Inbox.Split('@')
$done = 0
foreach ($id in $mgrIds) {
    $m = $hr | Where-Object EmployeeId -eq $id
    $prefix = $m.UserPrincipalName.Split('@')[0]
    $address = "$local+$prefix@$domain"
    try {
        Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/users/$($m.UserPrincipalName)" -Body @{ mail = $address }
        $done++
        Write-Host "  $($m.DisplayName) -> $address" -ForegroundColor Green
    } catch {
        Write-Host "Entra ID rejected setting mail to an external address:" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Use the fallback: issue each joiners TAP in the portal on their start day (walkthrough Step 8)." -ForegroundColor Yellow
        if ($done -eq 0) { exit 1 } else { throw }
    }
}
Write-Host "$done manager(s) now notify $Inbox" -ForegroundColor Cyan
