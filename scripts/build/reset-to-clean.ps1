<#
.SYNOPSIS
    Nordwind AD Lab - Revert all Phase 2 sabotages, returning the domain to a
    clean (healthy) baseline.

.DESCRIPTION
    The build scripts (01-05) stand up a HEALTHY domain. Phase 2 then plants three
    deliberate misconfigurations (see docs/phase2-sabotage.md), and Phase 3 exploits
    them all the way to Domain Admin + DCSync (see docs/phase3-attack.md).

    This script undoes that damage so the lab can be re-attacked from a known-good
    state WITHOUT rebuilding the VMs from zero. It reverses, in safe order:

        1. ACL abuse   -> remove the planted ACEs (piotr->robert, robert->Domain Admins)
                          and evict any illegitimate Domain Admins member.
        2. AS-REP      -> re-enable Kerberos pre-authentication on piotr.
        3. Kerberoast  -> unregister the SPN and remove the svc_sql account
                          (it did not exist in the clean build).

    Order matters: ACLs/membership are cleaned FIRST, so that removing accounts or
    flags can't leave a dangling privileged escalation path mid-run.

    This is my own addition to the lab; the upstream base (Maciej Stawowy, MIT) has
    no offensive phase and therefore no cleanup counterpart.

.NOTES
    Run on DC01 in an elevated PowerShell session (RSAT ActiveDirectory module).
    Idempotent: safe to run multiple times; each step checks state before acting.

    Author: Jorge Escobar
#>

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$domainNB = 'NORDWIND'

Write-Host "=== Nordwind: reverting Phase 2 sabotages -> clean baseline ===" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. ACL abuse (sabotage #3) — remove planted ACEs + evict illegitimate DA member
#    WHY first: as long as robert can write to Domain Admins, the path is live.
#    Kill the path (membership + ACEs) before touching anything else.
# -----------------------------------------------------------------------------
Write-Host "`n[1] Reverting ACL abuse..." -ForegroundColor Cyan

$daGroup = Get-ADGroup 'Domain Admins'
$daDN    = $daGroup.DistinguishedName

# 1a. Evict robert from Domain Admins if the attack added him (DA is the prize).
$daMembers = Get-ADGroupMember -Identity $daGroup -Recursive |
             Where-Object { $_.SamAccountName -eq 'robert.dabrowski' }
if ($daMembers) {
    Remove-ADGroupMember -Identity $daGroup -Members 'robert.dabrowski' -Confirm:$false
    Write-Host "  [+] Removed robert.dabrowski from Domain Admins" -ForegroundColor Green
} else {
    Write-Host "  [=] robert.dabrowski not in Domain Admins (nothing to do)" -ForegroundColor Yellow
}

# 1b. Strip the ACE that let robert control the Domain Admins group (GenericAll).
#     dsacls /R removes ALL allow/deny ACEs for that trustee on the object.
if (Get-ADUser -Filter "SamAccountName -eq 'robert.dabrowski'" -ErrorAction SilentlyContinue) {
    dsacls "$daDN" /R "${domainNB}\robert.dabrowski" | Out-Null
    Write-Host "  [+] Removed robert's ACEs on 'Domain Admins'" -ForegroundColor Green
}

# 1c. Strip the ACE that let piotr force-change robert's password.
$robert = Get-ADUser -Filter "SamAccountName -eq 'robert.dabrowski'" -ErrorAction SilentlyContinue
if ($robert -and (Get-ADUser -Filter "SamAccountName -eq 'piotr.wisniewski'" -ErrorAction SilentlyContinue)) {
    dsacls "$($robert.DistinguishedName)" /R "${domainNB}\piotr.wisniewski" | Out-Null
    Write-Host "  [+] Removed piotr's ACEs on robert" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 2. AS-REP roasting (sabotage #2) — re-enable Kerberos pre-authentication
#    WHY: with preauth ON, no AS-REP can be requested without the account's key.
# -----------------------------------------------------------------------------
Write-Host "`n[2] Reverting AS-REP roasting..." -ForegroundColor Cyan

$piotr = Get-ADUser -Filter "SamAccountName -eq 'piotr.wisniewski'" -Properties DoesNotRequirePreAuth -ErrorAction SilentlyContinue
if ($piotr) {
    if ($piotr.DoesNotRequirePreAuth) {
        Set-ADAccountControl -Identity 'piotr.wisniewski' -DoesNotRequirePreAuth $false
        Write-Host "  [+] Re-enabled pre-authentication on piotr.wisniewski" -ForegroundColor Green
    } else {
        Write-Host "  [=] piotr already requires pre-auth (nothing to do)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [!] piotr.wisniewski not found — skipping" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 3. Kerberoasting (sabotage #1) — unregister the SPN and remove svc_sql
#    WHY: no SPN => the account is not Kerberoastable. svc_sql did not exist in the
#    clean build, so removing it fully restores the baseline.
# -----------------------------------------------------------------------------
Write-Host "`n[3] Reverting Kerberoasting..." -ForegroundColor Cyan

$spn = 'MSSQLSvc/dc01.nordwind.local:1433'
if (Get-ADUser -Filter "SamAccountName -eq 'svc_sql'" -ErrorAction SilentlyContinue) {
    # Unregister the SPN first (harmless if already gone), then delete the account.
    setspn -D $spn svc_sql 2>$null | Out-Null
    Remove-ADUser -Identity 'svc_sql' -Confirm:$false
    Write-Host "  [+] Unregistered SPN and removed svc_sql" -ForegroundColor Green
} else {
    Write-Host "  [=] svc_sql does not exist (nothing to do)" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
Write-Host "`n[*] Verification:" -ForegroundColor Cyan
Write-Host "  Domain Admins members:" -ForegroundColor White
Get-ADGroupMember 'Domain Admins' | Select-Object -ExpandProperty SamAccountName | ForEach-Object { Write-Host "    - $_" }
Write-Host "  piotr DoesNotRequirePreAuth:" -ForegroundColor White
(Get-ADUser piotr.wisniewski -Properties DoesNotRequirePreAuth).DoesNotRequirePreAuth
Write-Host "  svc_sql exists:" -ForegroundColor White
[bool](Get-ADUser -Filter "SamAccountName -eq 'svc_sql'" -ErrorAction SilentlyContinue)

Write-Host "`nDone. Domain returned to clean baseline." -ForegroundColor Green

# -----------------------------------------------------------------------------
# NOTE — krbtgt after a DCSync (Phase 3)
#   A full DCSync dumped the krbtgt hash, which means Golden Tickets could be
#   forged indefinitely. This script does NOT auto-rotate krbtgt (doing it wrong
#   breaks the domain). To fully evict that persistence, reset the krbtgt password
#   TWICE, waiting for replication between resets. In this single-DC lab, a VM
#   snapshot restore is the cleaner reset for the krbtgt concern specifically.
# -----------------------------------------------------------------------------
