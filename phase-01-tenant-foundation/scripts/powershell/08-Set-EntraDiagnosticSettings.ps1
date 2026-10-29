#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources, Az.OperationalInsights
<#
.SYNOPSIS
    Creates the identity Log Analytics workspace and streams Entra ID logs to it.

.DESCRIPTION
    Why: Entra ID keeps sign-in and audit logs for 30 days. Incident
    investigations and audit sampling routinely need more, and KQL detections
    (Phase 14) need the data in a queryable workspace.

    Cost controls:
      - 90-day retention (enough for quarterly audit sampling)
      - Daily ingestion cap, so a noisy log category can't run up a bill
      - Sentinel NOT enabled yet (its free trial starts when enabled; Phase 14)

    Requires: an Azure subscription (walkthrough Step 9) and an account that is
    both Global Administrator / Security Administrator in Entra ID AND Owner or
    Contributor on the subscription. Run as adm.daniel.opara.
#>
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [string] $Location       = 'eastus',
    [string] $ResourceGroup  = 'rg-danotech-identity-prd-eus',
    [string] $WorkspaceName  = 'log-danotech-identity-prd-eus',
    [int]    $RetentionDays  = 90,
    [double] $DailyCapGb     = 1,
    [string] $SettingName    = 'diag-entra-to-log-identity'
)

Connect-AzAccount -Tenant 'danotechinc.onmicrosoft.com' -Subscription $SubscriptionId | Out-Null

$tags = @{ owner = 'IAM'; phase = '01'; costCenter = 'CC5000'; environment = 'prd' }

if (-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroup -Location $Location -Tag $tags | Out-Null
    Write-Host "Created resource group $ResourceGroup" -ForegroundColor Green
}

$ws = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName -ErrorAction SilentlyContinue
if (-not $ws) {
    $ws = New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName `
        -Location $Location -Sku PerGB2018 -RetentionInDays $RetentionDays -Tag $tags
    Write-Host "Created workspace $WorkspaceName" -ForegroundColor Green
}
Set-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName -DailyQuotaGb $DailyCapGb | Out-Null
Write-Host "Retention $RetentionDays days, daily cap $DailyCapGb GB" -ForegroundColor Green

# Entra ID log categories. Each one feeds a later phase.
$categories = @(
    'AuditLogs',                     # every directory change (Phases 04-13 evidence)
    'SignInLogs',                    # interactive user sign-ins
    'NonInteractiveUserSignInLogs',  # token refreshes, app-on-behalf sign-ins
    'ServicePrincipalSignInLogs',    # app-only sign-ins (automation app, Phase 10)
    'ManagedIdentitySignInLogs',     # managed identities (Phase 10)
    'ProvisioningLogs',              # HR feed and SCIM to SaaS (Phases 04, 08)
    'RiskyUsers', 'UserRiskEvents',  # ID Protection (Phases 07, 15)
    'RiskyServicePrincipals', 'ServicePrincipalRiskEvents',
    'MicrosoftGraphActivityLogs'     # every Graph API call; detects token misuse (Phase 15)
)

$body = @{
    properties = @{
        workspaceId = $ws.ResourceId
        logs        = @($categories | ForEach-Object { @{ category = $_; enabled = $true } })
    }
} | ConvertTo-Json -Depth 5

$res = Invoke-AzRestMethod -Method PUT -Payload $body `
    -Path "/providers/microsoft.aadiam/diagnosticSettings/$($SettingName)?api-version=2017-04-01"
if ($res.StatusCode -ge 300) { throw "Diagnostic setting failed ($($res.StatusCode)): $($res.Content)" }

Write-Host "Diagnostic setting '$SettingName' streaming $($categories.Count) categories to $WorkspaceName" -ForegroundColor Green
Write-Host "Logs take 15-30 minutes to appear. Verify with kql/pipeline-health.kql." -ForegroundColor Cyan
Write-Host "Workspace ID (for alerts): $($ws.CustomerId)" -ForegroundColor Cyan
