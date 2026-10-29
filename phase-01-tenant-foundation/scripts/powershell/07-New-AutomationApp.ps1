#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Creates app-danotech-iam-automation: the identity unattended scripts run as.

.DESCRIPTION
    Why an app registration: scheduled jobs (reports, HR feed uploads,
    posture checks) can't do interactive MFA, and running them as a human
    admin would mean storing that admin's credentials. An app identity has
    its own auditable sign-ins and only the permissions it's granted.

    Why a certificate, not a client secret: a secret is a password in a
    config file. A certificate's private key stays in the local certificate
    store (or Key Vault) and only the public key is uploaded to Entra ID.

    Why read-only: this phase only needs reporting. Each later phase adds the
    specific write permission it needs, through a reviewed pull request, so
    the permission list documents exactly why each right exists.

    On Windows the certificate is created in Cert:\CurrentUser\My. On macOS or
    Linux, create one with openssl (see walkthrough Step 10) and pass -CertificatePath.

    Run as adm.daniel.opara.
#>
param(
    [string] $DisplayName = 'app-danotech-iam-automation',
    [string] $CertificatePath,      # .cer public key (macOS/Linux)
    [int]    $CertValidityMonths = 12
)

. (Join-Path $PSScriptRoot '..\..\..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'User.Read'

# Permissions granted in Phase 01. Every entry has a reason; keep it that way.
$permissions = [ordered]@{
    'Directory.Read.All'           = 'Read users, groups and directory objects for reporting'
    'Policy.Read.All'              = 'Read Conditional Access and authorization policies for drift checks'
    'AuditLog.Read.All'            = 'Read sign-in and audit logs via Graph'
    'RoleManagement.Read.Directory'= 'Report who holds which admin role'
}

# --- Certificate -------------------------------------------------------------
if ($CertificatePath) {
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
}
elseif ($IsWindows) {
    $cert = New-SelfSignedCertificate -Subject "CN=$DisplayName" -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddMonths($CertValidityMonths)
    Write-Host "Created certificate $($cert.Thumbprint) in Cert:\CurrentUser\My" -ForegroundColor Green
}
else { throw 'On macOS/Linux, create a certificate with openssl and pass -CertificatePath <file.cer>.' }

# --- App registration --------------------------------------------------------
$graphAppId = '00000003-0000-0000-c000-000000000000'
$graphSp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '$graphAppId'").value[0]
$roleIds = foreach ($p in $permissions.Keys) {
    $r = $graphSp.appRoles | Where-Object { $_.value -eq $p }
    if (-not $r) { throw "Graph app role '$p' not found" }
    $r.id
}

$app = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/applications?`$filter=displayName eq '$DisplayName'").value | Select-Object -First 1
if (-not $app) {
    $me = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/me?$select=id'
    $app = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/applications' -Body @{
        displayName    = $DisplayName
        signInAudience = 'AzureADMyOrg'      # single tenant: nobody outside DanotechInc can use it
        notes          = 'Owner: IAM team. Purpose: unattended IAM automation. Permissions are added per phase via PR. Do not add client secrets.'
        requiredResourceAccess = @(@{
            resourceAppId  = $graphAppId
            resourceAccess = @($roleIds | ForEach-Object { @{ id = $_; type = 'Role' } })
        })
        keyCredentials = @(@{
            type        = 'AsymmetricX509Cert'
            usage       = 'Verify'
            key         = [Convert]::ToBase64String($cert.RawData)
            displayName = "CN=$DisplayName"
        })
    }
    Invoke-MgGraphRequest -Method POST -Uri "v1.0/applications/$($app.id)/owners/`$ref" -Body @{
        '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($me.id)"
    }
    Write-Host "Created app registration $DisplayName ($($app.appId))" -ForegroundColor Green
    Start-Sleep -Seconds 10
}

$sp = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '$($app.appId)'").value | Select-Object -First 1
if (-not $sp) {
    $sp = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/servicePrincipals' -Body @{ appId = $app.appId }
    Start-Sleep -Seconds 10
}

# --- Admin consent: assign each Graph app role to the service principal --------
$granted = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$($sp.id)/appRoleAssignments").value
foreach ($i in 0..($roleIds.Count - 1)) {
    $rid = $roleIds[$i]; $name = @($permissions.Keys)[$i]
    if ($granted | Where-Object { $_.appRoleId -eq $rid }) { continue }
    Invoke-MgGraphRequest -Method POST -Uri "v1.0/servicePrincipals/$($sp.id)/appRoleAssignments" -Body @{
        principalId = $sp.id; resourceId = $graphSp.id; appRoleId = $rid
    } | Out-Null
    Write-Host "Granted $name - $($permissions[$name])" -ForegroundColor Green
}

Write-Host "`nSet these environment variables for app-only scripts:" -ForegroundColor Cyan
Write-Host "  `$env:DANOTECH_AUTOMATION_CLIENT_ID = '$($app.appId)'"
Write-Host "  `$env:DANOTECH_AUTOMATION_CERT_THUMBPRINT = '$($cert.Thumbprint)'"
Write-Host "Test with: Connect-Danotech -AppOnly" -ForegroundColor Cyan
