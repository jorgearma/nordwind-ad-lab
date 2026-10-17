<#
.SYNOPSIS
    Nordwind AD Lab - Phase 2, Sabotage #1: Kerberoastable service account.

.DESCRIPTION
    Creates a service account (svc_sql) with a WEAK password and registers an SPN,
    making it vulnerable to Kerberoasting. Deliberate misconfiguration for a
    controlled lab. See docs/phase2-sabotage.md.

.NOTES
    Run on DC01 in an elevated PowerShell session (RSAT ActiveDirectory module).
    Take a VM snapshot before running.
#>

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$ouPath   = 'OU=ServiceAccounts,OU=Nordwind,DC=nordwind,DC=local'
$sam      = 'svc_sql'
$weakPass = 'Summer2023!'
$spn      = 'MSSQLSvc/dc01.nordwind.local:1433'

# 1. Create the service account with a weak, non-expiring password.
if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
    Write-Host "[i] $sam already exists - skipping creation." -ForegroundColor Yellow
} else {
    New-ADUser -Name $sam -SamAccountName $sam `
        -UserPrincipalName "$sam@nordwind.local" `
        -Path $ouPath `
        -AccountPassword (ConvertTo-SecureString $weakPass -AsPlainText -Force) `
        -Enabled $true -PasswordNeverExpires $true `
        -Description 'SQL service account (lab - intentionally weak password)'
    Write-Host "[+] Created $sam" -ForegroundColor Green
}

# 2. Register the SPN -> this is what makes the account Kerberoastable.
setspn -A $spn $sam

# 3. Verify.
Write-Host "[*] SPNs for $sam :" -ForegroundColor Cyan
setspn -L $sam
