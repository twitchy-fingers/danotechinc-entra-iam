<#
.SYNOPSIS
    Shared connection helper for every DanotechInc script.

.DESCRIPTION
    Connects to Microsoft Graph in one of two modes:
      - Interactive (default): a human admin signs in and consents to only the
        scopes the calling script needs. Used for one-off setup steps.
      - App-only (-AppOnly): the automation app registration from Phase 01
        signs in with a certificate. Used for unattended jobs.

    Centralising this means tenant ID and app details live in one place, and
    every script requests explicit, minimal scopes rather than "everything".

.EXAMPLE
    . ../../scripts/common/Connect-Danotech.ps1
    Connect-Danotech -Scopes 'User.Read.All','Policy.Read.All'

.EXAMPLE
    Connect-Danotech -AppOnly
#>

$script:DanotechTenantDomain = 'danotechinc.onmicrosoft.com'

function Connect-Danotech {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(ParameterSetName = 'Interactive', Mandatory)]
        [string[]] $Scopes,

        [Parameter(ParameterSetName = 'AppOnly', Mandatory)]
        [switch] $AppOnly,

        [Parameter(ParameterSetName = 'AppOnly')]
        [string] $ClientId = $env:DANOTECH_AUTOMATION_CLIENT_ID,

        [Parameter(ParameterSetName = 'AppOnly')]
        [string] $CertificateThumbprint = $env:DANOTECH_AUTOMATION_CERT_THUMBPRINT
    )

    if ($PSCmdlet.ParameterSetName -eq 'AppOnly') {
        if (-not $ClientId -or -not $CertificateThumbprint) {
            throw 'Set DANOTECH_AUTOMATION_CLIENT_ID and DANOTECH_AUTOMATION_CERT_THUMBPRINT (see Phase 01, Step 9).'
        }
        Connect-MgGraph -TenantId $script:DanotechTenantDomain -ClientId $ClientId `
            -CertificateThumbprint $CertificateThumbprint -NoWelcome
    }
    else {
        Connect-MgGraph -TenantId $script:DanotechTenantDomain -Scopes $Scopes -NoWelcome
    }

    $ctx = Get-MgContext
    Write-Host ("Connected to {0} as {1} ({2})" -f $ctx.TenantId, ($ctx.Account ?? $ctx.AppName), $ctx.AuthType) -ForegroundColor Green
}
