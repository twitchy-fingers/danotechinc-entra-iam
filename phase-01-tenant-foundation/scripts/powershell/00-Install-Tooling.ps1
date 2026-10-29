#Requires -Version 7.2
<#
.SYNOPSIS
    Installs the PowerShell modules used across the DanotechInc program.

.DESCRIPTION
    - Microsoft.Graph       : all Entra ID configuration (v1.0 endpoints)
    - Microsoft.Graph.Beta  : features only available on the beta endpoint (used sparingly, always noted)
    - Az.Accounts, Az.Resources, Az.OperationalInsights, Az.Monitor : Azure resources for logging and RBAC

    Modules install for the current user only, so no local admin rights are needed.
#>
$modules = @(
    'Microsoft.Graph',
    'Microsoft.Graph.Beta',
    'Az.Accounts',
    'Az.Resources',
    'Az.OperationalInsights',
    'Az.Monitor'
)

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

foreach ($m in $modules) {
    if (Get-Module -ListAvailable -Name $m) {
        Write-Host "Updating $m" -ForegroundColor Cyan
        Update-Module -Name $m -Scope CurrentUser -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "Installing $m" -ForegroundColor Cyan
        Install-Module -Name $m -Scope CurrentUser -AllowClobber -Force
    }
}

Write-Host "`nInstalled versions:" -ForegroundColor Green
Get-Module -ListAvailable -Name $modules |
    Sort-Object Name, Version -Descending |
    Group-Object Name | ForEach-Object { $_.Group[0] } |
    Format-Table Name, Version
