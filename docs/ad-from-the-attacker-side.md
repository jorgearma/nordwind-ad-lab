# Active Directory from the Attacker's Side

> A **build → break → understand** walkthrough, built on top of a lab I stood up by hand
> (see the rest of this repo). The goal isn't to hand you commands — it's to make you
> understand **why** each attack works, so you can explain it without naming the tool.

**Who this is for:** people who can *run* AD tools (`GetNPUsers`, `BloodHound`, `secretsdump`)
but want to understand the protocols underneath — the gap between copy-pasting and actually
having a level. Think OSCP / CRTP preparation, or a blue-teamer who wants to see their domain
through an attacker's eyes.

**Status:** living document. The AS-REP Roasting stop is fully written; the rest are stubbed
with their one-line essence and filled in one stop per pass.

---

## 0. Why this document is different

Most AD guides online are *tool references*: "run this, get that." This one is the opposite.
I **built** `nordwind.local` from an empty VM, **sabotaged** it on purpose with specific
misconfigurations, and then **attacked** it from zero credentials to Domain Admin. Because I
planted every hole myself, I can tell you exactly *why* each attack works — not just that it does.

So every stop below follows the same **4-box pattern**:

| Box | Question it answers |
|-----|---------------------|
| **What it is** | The attack in one honest sentence (the protocol story, not the tool). |
| **Why it works** | The specific misconfiguration or design fact that enables it. |
| **What it looks like** | The commands and the *expected output* — what you'd actually see. |
| **How it's defended** | What a blue-teamer changes to kill it (and how it's detected). |

Everything here is **manual and OSCP-friendly** — no Metasploit.

---

## 1. The mental model of AD in 5 pillars

> The tools are easy to *use*; the hard part is the **concept** underneath. That's where the
> level is. If I take the tool away and you can still explain what it does and why it works,
> you have a level. If you only know the command, you're copy-paste.

| # | Pillar | The one thing to get | What it unlocks |
|---|--------|----------------------|-----------------|
| 1 🥇 | **Kerberos** | The dance `AS-REQ → AS-REP (TGT) → TGS-REQ → TGS-REP`, and what *pre-authentication* is. | AS-REP Roasting, Kerberoasting, Pass-the-Ticket, Golden/Silver tickets, delegation. Half a dozen attacks from one protocol. |
| 2 🥈 | **NTLM / Pass-the-Hash** | Why, for NTLM auth, **the hash *is* the password** (no cracking needed). | PtH, lateral movement by reusing hashes, why `secretsdump` is so powerful. |
| 3 🥉 | **ACLs / DACLs** | What an **ACE** is, and what `GenericAll` / `WriteDacl` / `WriteOwner` / `GenericWrite` let you do — and how they **chain**. | Everything BloodHound draws; privilege escalation through object permissions. |
| 4 | **AD structure / LDAP** | Objects, OUs, **SID/RID**, and **nested group membership** (a group inside a group inherits permissions). | Enumeration that makes sense; *why* a user inherits rights they didn't seem to have. |
| 5 | **DCSync / replication** | Why a principal with the right permission can ask the DC to **replicate secrets to it**, as if it were another DC. | The finishing move of most AD compromises — "impersonating a Domain Controller." |

**If you prioritize:** master **Kerberos + NTLM/PtH + ACLs**. With those three you can explain
half of any AD box. LDAP and DCSync you finish off quickly. It's not 50 hard things — it's 5
pillars, and Kerberos weighs as much as three.

**The honest level test:** can you tell the attack as a *story about the protocol* without
naming the tool?
- ❌ "AS-REP Roasting is `GetNPUsers`." → copy-paste.
- ✅ "AS-REP Roasting works because an account without pre-authentication makes the KDC hand me
  an AS-REP containing a blob encrypted with the hash of its password, which I crack offline."
  → **real level.**

---

## 2. The attacker's mindset: "everything is a principal with a SID"

Before the attacks, one mental switch that makes all of them click:

- A **user**, a **service account**, and a **group** are the same kind of thing to an attacker:
  objects with a **SID**, that can **hold permissions over other objects**. A service account is
  a principal just like a user — which is exactly why it's useful for ACL abuse.
- **One plain, unprivileged account maps the entire domain.** LDAP is readable by *any*
  authenticated principal. So the moment you have *any* foothold, you can enumerate every user,
  group, ACL and trust — and feed it to BloodHound.
- **BloodHound is a snapshot in time.** Collect data *first*, exploit *after*: if you change the
  domain (reset a password, trip a protection like AdminSDHolder/SDProp), the graph you relied on
  may no longer match reality.

---

## 3. The walkthrough

Each stop uses the 4-box pattern from §0. They're ordered the way a real attack flows: from
**zero credentials** to **owning the domain**.

### 3.1 Enumeration without credentials
> **In one sentence:** before any exploit, you turn "I only have network access to a DC" into a
> list of valid usernames — using null sessions and Kerberos, no password required.

🚧 *Detailed walkthrough coming in a future pass (`rpcclient -U "" -N`, `enum4linux-ng`, RID
cycling, `kerbrute userenum`). This is the one link my own lab handed me for free — the next box
I practice on HTB Forest.*

---

### 3.2 AS-REP Roasting ✅

#### What it is
An account with **Kerberos pre-authentication disabled** makes the KDC hand its **AS-REP** to
*anyone* who asks for it by name — without proving anything. That AS-REP is encrypted with the
**hash of the user's password**, so you take it and crack it **offline**. You need **zero
credentials** — just a valid username.

#### Why it works
In a normal Kerberos login, **pre-authentication** means your client encrypts a **timestamp**
with your password hash, and the KDC decrypts it with the hash it stores. If it matches, it knows
you really are you, and only *then* sends the AS-REP. It's an **anti-cracking lock**: it forces
you to prove identity *before* you receive anything encrypted with your hash.

There is a checkbox in AD — **"Do not require Kerberos pre-authentication"**
(`DONT_REQ_PREAUTH`). With it set:

> The KDC sends the **AS-REP to anyone** who names the account, **without asking for the encrypted
> timestamp.**

The key insight: pre-auth never stopped you from *cracking* the hash — it stopped you from
*obtaining the blob without proving identity*. Remove it, and a stranger walks off with the blob
knowing only the username. Weak password → `hashcat` cracks it offline in seconds.

**Why would an admin ever disable it?** Old apps/devices (legacy Linux/Unix) that don't implement
Kerberos pre-auth properly → the admin turns the checkbox off "to make it work" → leaves the door
open. It tends to land on **IT / technical** accounts.

#### What it looks like
*The sabotage I planted (on DC01):*
```powershell
# victim: piotr.wisniewski (OU=IT), weak password set on purpose for the lab
Set-ADAccountControl -Identity piotr.wisniewski -DoesNotRequirePreAuth $true
Get-ADUser piotr.wisniewski -Properties DoesNotRequirePreAuth | Select Name,DoesNotRequirePreAuth
#   DoesNotRequirePreAuth : True   <- the hole
```

*The attack (from Kali, no credentials):*
```bash
# Fire a username list at the KDC. In a real engagement you'd get the list first
# (kerbrute / RID cycling, see §3.1).
impacket-GetNPUsers nordwind.local/ -usersfile users.txt -no-pass \
  -dc-ip 192.168.10.10 -format hashcat -outputfile asrep.txt
```
**Expected output:** only `piotr.wisniewski` drops a hash; everyone else returns
`doesn't have UF_DONT_REQUIRE_PREAUTH set`. That's the logic in action — you spray the whole
list and **only the misconfigured account falls**:
```
$krb5asrep$23$piotr.wisniewski@NORDWIND.LOCAL:a1b2...
```
```bash
hashcat -m 18200 asrep.txt wordlist.txt      # -> piotr : Autumn2024!
```
> **Wordlist lesson (matters for OSCP):** `Autumn2024!` is **not** in rockyou — it's a
> *season+year+symbol* pattern, not a real leak. It cracked with a **targeted wordlist** built by
> hand for that pattern. Mode `18200` = AS-REP (don't confuse it with `13100` = Kerberoasting).

Validate the credential before moving on:
```bash
netexec smb 192.168.10.10 -u piotr.wisniewski -p 'Autumn2024!'   # -> [+]
```

#### How it's defended
1. **Never disable pre-auth** unless there's a documented critical need — audit the whole user
   base for the checkbox.
2. If a legacy app forces it → **isolate** that account and give it a **long, random password**
   (uncrackable).
3. **Audit** periodically which accounts have `DONT_REQ_PREAUTH` (BloodHound shows it directly).
4. **Monitor** Event ID **4768** (AS-REQ) with pre-auth type 0 / RC4 encryption.

#### Where it lands in the OSCP
The AD set (40 pts): one of the **first** shots, because it needs no credentials. Enumerate users
→ `GetNPUsers` the list → if one falls, you have a starting credential. 100% manual, no Metasploit.

---

### 3.3 Kerberoasting
> **In one sentence:** as *any* authenticated user, you request a service ticket (TGS) for an
> account that has an **SPN**; the ticket comes encrypted with that service account's hash, which
> you crack offline. Needs credentials (unlike AS-REP), targets service accounts.

🚧 *Detailed 4-box walkthrough coming next pass (`GetUserSPNs.py`, hashcat `-m 13100`, the
`svc_sql` sabotage, and what to do with a cracked MSSQL service account → `xp_cmdshell` → SYSTEM).*

---

### 3.4 ACL abuse → Domain Admins (+ AdminSDHolder / SDProp)
> **In one sentence:** you don't need to *steal* a credential if you have *write* permission over
> an object — the permission itself is the attack. Chained ACEs turn a foothold into Domain Admin.

🚧 *Detailed walkthrough coming (the `piotr → ForceChangePassword → robert → GenericAll → Domain
Admins` chain; `dsacls`; and the live lesson where **AdminSDHolder/SDProp** dismantled the chain
and I had to win the race against it).*

---

### 3.5 DCSync
> **In one sentence:** a principal with replication rights asks the DC to replicate account secrets
> to it, as if it were another Domain Controller — dumping `krbtgt` and `Administrator` hashes.

🚧 *Detailed walkthrough coming (`secretsdump.py`, the DRSUAPI right, and why owning `krbtgt` means
Golden Ticket persistence — and how `reset-to-clean.ps1` does/doesn't address it).*

---

## 4. Build your own lab to practice

Reading about these attacks is a fraction of the value — planting the hole yourself and then
exploiting it is where it clicks. This whole repo *is* that lab:

1. **Stand up the clean domain** — [`scripts/build/`](../scripts/build/) provisions OUs, 10 users
   and the AGDLP groups on a fresh Windows Server 2022 DC. Run order and rationale in its
   [README](../scripts/build/README.md).
2. **Plant the holes** — the Phase 2 sabotage scripts
   ([`scripts/`](../scripts/)) create exactly the three misconfigurations this walkthrough attacks.
   Full write-up: [`docs/phase2-sabotage.md`](phase2-sabotage.md).
3. **Attack it** — the end-to-end chain, zero credentials → Domain Admin → DCSync, is in
   [`docs/phase3-attack.md`](phase3-attack.md).
4. **Re-arm it** — [`scripts/build/reset-to-clean.ps1`](../scripts/build/reset-to-clean.ps1)
   reverts the sabotages so you can re-attack from a clean baseline without rebuilding the VMs.

> The base infrastructure is vendored (with attribution) from
> [Maciej Stawowy's lab](https://github.com/maciej-stawowy/active-directory-lab) (MIT). The
> offensive layer and this walkthrough are mine.

---

## 5. What's next / resources

- **Finish the stops:** §3.1 enumeration, §3.3 Kerberoasting, §3.4 ACL abuse, §3.5 DCSync.
- **Practice targets that mirror this chain:** HTB *Forest* (AS-REP → BloodHound → DCSync) and
  *Sauna* are almost a 1:1 with the Nordwind chain.
- **Go deeper:** the concepts here are the floor, not the ceiling — delegation (unconstrained /
  constrained / RBCD), Golden/Silver tickets, and trust abuse are the natural next layer.

---

*Built and written by Jorge Escobar as part of OSCP / CRTP preparation. Feedback welcome.*
