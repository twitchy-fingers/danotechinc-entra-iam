#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Creates DanotechInc's two emergency access (break-glass) accounts.

.DESCRIPTION
    1. Enables the Passkey (FIDO2) authentication method, so the accounts can
       register phishing-resistant credentials.
    2. Creates a role-assignable security group used to exclude the accounts
       from every Conditional Access policy.
    3. Creates two cloud-only accounts with long random passwords.
    4. Adds both to the exclusion group.
    5. Assigns Global Administrator permanently (active, not PIM-eligible).

    Idempotent: re-running skips anything that already exists.

    The generated passwords are shown ONCE on screen and never written to disk.
    Have the storage method ready before running (see the walkthrough, Step 3).

.EXAMPLE
    ./02-New-BreakGlassAccounts.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param()

. (Join-Path $PSScriptRoot '..\..\..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'Policy.ReadWrite.AuthenticationMethod'

$domain           = 'danotechinc.onmicrosoft.com'
$globalAdminRoleId= '62e90394-69f5-4237-9190-012177145e10'   # Global Administrator role template ID
$groupName        = 'GRP-CA-Exclude-BreakGlass'

function New-StrongPassword([int] $Length = 64) {
    # Cryptographically random, from a set that avoids look-alike characters,
    # because this password may one day be typed from a printed copy under pressure.
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*-_=+'
    -join (1..$Length | ForEach-Object { $chars[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)] })
}

function New-RandomToken([int] $Length = 4) {
    $chars = 'abcdefghjkmnpqrstuvwxyz23456789'
    -join (1..$Length | ForEach-Object { $chars[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)] })
}

# --- 1. Enable passkeys (FIDO2) ---------------------------------------------
# Why: mandatory MFA applies to admin portals, so break-glass accounts need an
# MFA method. FIDO2 keys are phishing-resistant and don't depend on a phone.
# Targeting all users only makes the method *available*; it doesn't force anyone
# to register. Phase 07 refines this policy (key restrictions, attestation).
Write-Host 'Enabling Passkey (FIDO2) authentication method' -ForegroundColor Cyan
$fido2 = @{
    '@odata.type'                    = '#microsoft.graph.fido2AuthenticationMethodConfiguration'
    state                            = 'enabled'
    isSelfServiceRegistrationAllowed = $true
    isAttestationEnforced            = $false
    includeTargets                   = @(@{ targetType = 'group'; id = 'all_users'; isRegistrationRequired = $false })
}
Invoke-MgGraphRequest -Method PATCH -Uri 'v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2' -Body $fido2

# --- 2. Exclusion group -----------------------------------------------------
# Role-assignable groups can only be changed by Privileged Role Admins / Global
# Admins. That stops a User Administrator from adding themselves to the
# exclusion list and silently bypassing every CA policy.
$existing = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups?`$filter=displayName eq '$groupName'").value
if ($existing) {
    $group = $existing[0]
    Write-Host "Group $groupName already exists ($($group.id))" -ForegroundColor Yellow
}
else {
    $group = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/groups' -Body @{
        displayName        = $groupName
        description        = 'Emergency access accounts. Excluded from ALL Conditional Access policies. Membership changes alert the CISO. Owner: IAM Manager.'
        mailEnabled        = $false
        mailNickname       = 'grp-ca-exclude-breakglass'
        securityEnabled    = $true
        isAssignableToRole = $true
    }
    Write-Host "Created $groupName ($($group.id))" -ForegroundColor Green
}

# --- 3-5. Accounts ------------------------------------------------------------
$created = @()
foreach ($n in '01', '02') {
    $displayName = "Emergency Access $n"
    $found = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users?`$filter=displayName eq '$displayName'&`$select=id,userPrincipalName").value

    if ($found) {
        $user = $found[0]
        Write-Host "$displayName already exists ($($user.userPrincipalName))" -ForegroundColor Yellow
    }
    else {
        $upn = "bg-$(New-RandomToken)-$n@$domain"
        $password = New-StrongPassword
        if ($PSCmdlet.ShouldProcess($upn, 'Create break-glass account')) {
            $user = Invoke-MgGraphRequest -Method POST -Uri 'v1.0/users' -Body @{
                accountEnabled    = $true
                displayName       = $displayName
                mailNickname      = "bg-$n"
                userPrincipalName = $upn
                usageLocation     = 'US'
                passwordPolicies  = 'DisablePasswordExpiration'
                passwordProfile   = @{ password = $password; forceChangePasswordNextSignIn = $false }
            }
            $created += [pscustomobject]@{ UPN = $upn; Password = $password; ObjectId = $user.id }
            Start-Sleep -Seconds 10   # new objects take a few seconds to replicate before they can be referenced
        }
        else { continue }
    }

    # Group membership (ignore "already exists" errors on re-run)
    try {
        Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($group.id)/members/`$ref" -Body @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.id)"
        }
    } catch { if ($_.Exception.Message -notmatch 'already exist') { throw } }

    # Permanent Global Administrator
    $hasGa = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($user.id)' and roleDefinitionId eq '$globalAdminRoleId'").value
    if (-not $hasGa) {
        Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignments' -Body @{
            principalId      = $user.id
            roleDefinitionId = $globalAdminRoleId
            directoryScopeId = '/'
        } | Out-Null
        Write-Host "Assigned Global Administrator to $displayName" -ForegroundColor Green
    }
}

if ($created) {
    Write-Host "`n================  RECORD THESE NOW  ================" -ForegroundColor Red
    Write-Host 'Passwords are shown once and are not saved anywhere.' -ForegroundColor Red
    Write-Host 'Store each account in a SEPARATE location (see walkthrough Step 3).' -ForegroundColor Red
    $created | Format-List UPN, Password, ObjectId
    Write-Host '====================================================' -ForegroundColor Red
    Read-Host 'Press Enter once both credentials are stored, to clear the screen'
    Clear-Host
}

Write-Host "Break-glass object IDs (needed for the KQL alert in Step 12):" -ForegroundColor Cyan
(Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$($group.id)/members?`$select=id,userPrincipalName").value |
    ForEach-Object { [pscustomobject]@{ UPN = $_.userPrincipalName; ObjectId = $_.id } } | Format-Table -AutoSize
Write-Host "Exclusion group ID: $($group.id)" -ForegroundColor Cyan
