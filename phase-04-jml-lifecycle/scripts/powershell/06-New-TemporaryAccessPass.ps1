#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Issues one-time Temporary Access Passes to several people in a row.

.DESCRIPTION
    For a single person, use the portal (Users > the user > Authentication methods >
    Add authentication method > Temporary Access Pass). This script is for the bulk case,
    such as preparing the six Phase 05 demo personas.

    Each TAP is shown ONCE on screen, never written to disk, and the screen is cleared
    after you confirm it has been used or handed over.
.EXAMPLE
    ./06-New-TemporaryAccessPass.ps1 -UserPrincipalName rachel.okafor@danotechinc.onmicrosoft.com, ama.amoah@danotechinc.onmicrosoft.com
#>
param(
    [Parameter(Mandatory)] [string[]] $UserPrincipalName,
    [int] $LifetimeMinutes = 1440
)
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'UserAuthenticationMethod.ReadWrite.All'

foreach ($upn in $UserPrincipalName) {
    $tap = Invoke-MgGraphRequest -Method POST -Uri "v1.0/users/$upn/authentication/temporaryAccessPassMethods" -Body @{
        lifetimeInMinutes = $LifetimeMinutes; isUsableOnce = $true }
    Write-Host "`nTAP for $upn (one-time, valid $LifetimeMinutes minutes):" -ForegroundColor Yellow
    Write-Host "    $($tap.temporaryAccessPass)" -ForegroundColor White
    Write-Host '  In a private window: https://aka.ms/mysecurityinfo, sign in with the TAP, add Microsoft Authenticator.'
    Read-Host '  Press Enter when done, to clear the screen and continue'
    Clear-Host
}
