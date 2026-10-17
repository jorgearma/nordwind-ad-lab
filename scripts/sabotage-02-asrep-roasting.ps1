<#
.SYNOPSIS
    Nordwind AD Lab - Phase 2, Sabotage #2: AS-REP-roastable account.

.DESCRIPTION
    Disables Kerberos pre-authentication on an existing user (piotr.wisniewski) and
    sets a WEAK password, making it vulnerable to AS-REP Roasting. Deliberate
    misconfiguration for a controlled lab. See docs/phase2-sabotage.md.

.NOTES
    Run on DC01 in an elevated PowerShell session (RSAT ActiveDirectory module).
    Take a VM snapshot before running.
#>

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$sam      = 'piotr.wisniewski'
$weakPass = 'Autumn2024!'

# Sanity check: the victim must already exist (created in Phase 1).
if (-not (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
    throw "User $sam not found. Create domain users (Phase 1) first."
}

# 1. Set a weak password so the AS-REP can be cracked offline in the lab.
Set-ADAccountPassword -Identity $sam -Reset `
    -NewPassword (ConvertTo-SecureString $weakPass -AsPlainText -Force)
Write-Host "[+] Weak password set on $sam" -ForegroundColor Green

# 2. Disable Kerberos pre-authentication -> the sabotage itself.
Set-ADAccountControl -Identity $sam -DoesNotRequirePreAuth $true
Write-Host "[+] Pre-authentication disabled on $sam" -ForegroundColor Green

# 3. Verify -> expect DoesNotRequirePreAuth : True
Write-Host "[*] Verifying flag:" -ForegroundColor Cyan
Get-ADUser -Identity $sam -Properties DoesNotRequirePreAuth |
    Select-Object Name, DoesNotRequirePreAuth
