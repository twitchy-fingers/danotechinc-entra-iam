#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Creates a dedicated admin account (adm.first.last) for a person.

.DESCRIPTION
    Why: the daily account reads email and browses the web, so it's the one
    most likely to be phished. Admin rights live on a separate account that is
    only ever used in admin portals.

    In Phase 01 this is used once, for the CEO. Phase 06 reuses the same
    pattern for the IAM team and converts the role to PIM-eligible.

    The account is created with a temporary password that must be changed at
    first sign-in. MFA registration is then forced by CA001/CA100 (Step 7).

.EXAMPLE
    ./03-New-AdminAccount.ps1 -FirstName Daniel -LastName Opara -EmployeeId DT01001 -Role 'Global Administrator'
#>
param(
    [Parameter(Mandatory)] [string] $FirstName,
    [Parameter(Mandatory)] [string] $LastName,
    [Parameter(Mandatory)] [string] $EmployeeId,
    [ValidateSet('Global Administrator')] [string] $Role = 'Global Administrator',
    [string] $UsageLocation = 'US'
)

. (Join-Path $PSScriptRoot '..\..\..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'User.ReadWrite.All', 'RoleManagement.ReadWrite.Directory'

$roleIds = @{ 'Global Administrator' = '62e90394-69f5-4237-9190-012177145e10' }
$slug = { param($s) ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '' -replace '[^a-zA-Z0-9]', '').ToLower() }
$upn  = "adm.$(& $slug $FirstName).$(& $slug $LastName)@danotechinc.onmicrosoft.com"

$existing = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users?`$filter=userPrincipalName eq '$upn'").value
if ($existing) {
    $user = $existing[0]
    Write-Host "$upn already exists" -ForegroundColor Yellow
}
else {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%*-'
    $temp  = -join (1..24 | ForEach-Object { $chars[[Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)] })

    $user = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/users' -Body @{
        accountEnabled    = $true
        displayName       = "ADM - $FirstName $LastName"
        givenName         = $FirstName
        surname           = $LastName
        mailNickname      = "adm.$(& $slug $FirstName).$(& $slug $LastName)"
        userPrincipalName = $upn
        usageLocation     = $UsageLocation
        # Same employeeId as the person's daily account: links the two for
        # access reviews and lets the leaver process find and disable both.
        employeeId        = $EmployeeId
        employeeType      = 'AdminAccount'
        jobTitle          = 'Privileged administrator account'
        passwordProfile   = @{ password = $temp; forceChangePasswordNextSignIn = $true }
    }
    Write-Host "Created $upn" -ForegroundColor Green
    Write-Host "Temporary password (change at first sign-in): $temp" -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

$roleId = $roleIds[$Role]
$has = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($user.id)' and roleDefinitionId eq '$roleId'").value
if (-not $has) {
    Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignments' -Body @{
        principalId = $user.id; roleDefinitionId = $roleId; directoryScopeId = '/'
    } | Out-Null
    Write-Host "Assigned $Role to $upn (active; becomes PIM-eligible in Phase 06)" -ForegroundColor Green
}
