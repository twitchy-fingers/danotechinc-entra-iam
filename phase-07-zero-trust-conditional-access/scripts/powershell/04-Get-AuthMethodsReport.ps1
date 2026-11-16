#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Checks the authentication methods policy and measures passkey adoption (objective O4).

.DESCRIPTION
    Policy checks (the portal settings from walkthrough Step 2):
      AM-01 Passkey (FIDO2) enabled for all users, self-service registration allowed
      AM-02 SMS and Voice call disabled (phishable, SIM-swappable)
      AM-03 Temporary Access Pass enabled and one-time only (Phase 04)
    Adoption, from Microsoft's registration report:
      - admin accounts with a passkey (target 100%) and the exact accounts still missing one
      - workforce passwordless-capable and MFA-registered (target >= 80% passkeys)
    Writes evidence\YYYYMMDD-auth-methods-adoption.csv.
#>
$ErrorActionPreference = 'Stop'
$phase = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $phase '..\scripts\common\Connect-Danotech.ps1')
Connect-Danotech -Scopes 'Policy.Read.All', 'AuditLog.Read.All', 'UserAuthenticationMethod.Read.All', 'User.Read.All'

$cfgs = @{}; (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/policies/authenticationMethodsPolicy').authenticationMethodConfigurations | ForEach-Object { $cfgs[$_.id] = $_ }
function Show([string] $id, [bool] $ok, [string] $what) { Write-Host ("  {0} {1}  {2}" -f ($ok ? 'PASS' : 'FAIL'), $id, $what) -ForegroundColor ($ok ? 'Green' : 'Red') }
Write-Host 'Authentication methods policy' -ForegroundColor Cyan
Show 'AM-01' ($cfgs['Fido2'].state -eq 'enabled' -and $cfgs['Fido2'].isSelfServiceRegistrationAllowed) 'Passkey (FIDO2) enabled, self-service registration allowed'
Show 'AM-02' ($cfgs['Sms'].state -ne 'enabled' -and $cfgs['Voice'].state -ne 'enabled') 'SMS and Voice call disabled'
Show 'AM-03' ($cfgs['TemporaryAccessPass'].state -eq 'enabled' -and $cfgs['TemporaryAccessPass'].isUsableOnce) 'Temporary Access Pass enabled, one-time use'

$uri = 'v1.0/reports/authenticationMethods/userRegistrationDetails?$top=999'
$reg = @(); while ($uri) { $p = Invoke-MgGraphRequest -Method GET -Uri $uri; $reg += $p.value; $uri = $p.'@odata.nextLink' }
$types = @{}; $uri = 'v1.0/users?$select=userPrincipalName,employeeType,accountEnabled,companyName&$top=999'
while ($uri) { $p = Invoke-MgGraphRequest -Method GET -Uri $uri; foreach ($u in $p.value) { $types[$u.userPrincipalName] = $u }; $uri = $p.'@odata.nextLink' }

$rows = foreach ($r in $reg) {
    $u = $types[$r.userPrincipalName]; if (-not $u -or -not $u.accountEnabled) { continue }
    $kind = if ($u.employeeType -eq 'AdminAccount') { 'Admin' } elseif ($r.userPrincipalName -like 'bg-*') { 'BreakGlass' } elseif ($u.companyName -eq 'DanotechInc') { 'Workforce' } else { 'Other' }
    $passkey = [bool]($r.methodsRegistered | Where-Object { $_ -match 'fido2|passKey' })
    [pscustomobject]@{ User = $r.userPrincipalName; Kind = $kind; Passkey = $passkey; PasswordlessCapable = $r.isPasswordlessCapable; MfaRegistered = $r.isMfaRegistered; Methods = ($r.methodsRegistered -join ',') }
}
Write-Host "`nAdoption" -ForegroundColor Cyan
foreach ($k in 'Admin', 'BreakGlass', 'Workforce') {
    $set = @($rows | Where-Object Kind -eq $k); if (-not $set) { continue }
    $pk = @($set | Where-Object Passkey).Count; $mfa = @($set | Where-Object MfaRegistered).Count
    Write-Host ("  {0,-10} {1,3} enabled · passkey {2,3} ({3:P0}) · any MFA {4,3} ({5:P0})" -f $k, $set.Count, $pk, ($pk / $set.Count), $mfa, ($mfa / $set.Count))
}
$missing = @($rows | Where-Object { $_.Kind -eq 'Admin' -and -not $_.Passkey })
if ($missing) { Write-Host "`nAdmin accounts WITHOUT a passkey (CA100 will block them):" -ForegroundColor Yellow; $missing.User | ForEach-Object { "  - $_" } }
$rows | Sort-Object Kind, User | Export-Csv (Join-Path $phase ("evidence\{0}-auth-methods-adoption.csv" -f (Get-Date -Format 'yyyyMMdd'))) -NoTypeInformation -Encoding utf8
