<#
.SYNOPSIS
    Nordwind AD Lab - Phase 2, Sabotage #3: abusable ACL chain to Domain Admin.

.DESCRIPTION
    Plants a 2-hop attack path via misconfigured ACLs (deliberate, for a controlled
    lab). See docs/phase2-sabotage.md.

        piotr.wisniewski --ForceChangePassword--> robert.dabrowski
        robert.dabrowski --GenericAll (group)---> Domain Admins

    Starting from a foothold on piotr (compromised via AS-REP Roasting), an attacker
    resets robert's password, then uses robert's control over the Domain Admins group
    to add themselves -> full domain compromise.

.NOTES
    Run on DC01 in an elevated PowerShell session (RSAT ActiveDirectory module).
    Take a VM snapshot before running.
#>

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$domainNB = 'NORDWIND'

# Resolve DNs so we never hand-type them.
$robertDN = (Get-ADUser  robert.dabrowski).DistinguishedName
$daDN     = (Get-ADGroup 'Domain Admins').DistinguishedName

# Hop 1: grant piotr ForceChangePassword over robert.
#   CA;"Reset Password" = Control Access extended right (User-Force-Change-Password).
dsacls "$robertDN" /G "${domainNB}\piotr.wisniewski:CA;Reset Password"
Write-Host "[+] piotr -> ForceChangePassword over robert" -ForegroundColor Green

# Hop 2: grant robert GenericAll over the Domain Admins group.
#   GA = Generic All (full control) -> lets robert add himself as a member.
dsacls "$daDN" /G "${domainNB}\robert.dabrowski:GA"
Write-Host "[+] robert -> GenericAll over 'Domain Admins'" -ForegroundColor Green

# Verify.
Write-Host "[*] Verifying ACLs:" -ForegroundColor Cyan
dsacls "$robertDN" | Select-String 'piotr'    # expect: Allow ... Reset Password
dsacls "$daDN"     | Select-String 'robert'   # expect: Allow ... FULL CONTROL
