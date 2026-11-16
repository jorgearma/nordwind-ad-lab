# Nordwind Logistics — Active Directory Lab

An **Active Directory** lab built from scratch, documenting the whole process end to end:
from infrastructure design to offensive exploitation.

Learning and portfolio project — **Jorge Escobar** (OSCP / CRTP preparation).

---

## Live site

**[▶ Open the site](https://jorgearma.github.io/nordwind-ad-lab/)** — the front page, laid out like
a small blog: the attack replay as the featured entry, then "How AD works inside" and the domain
explorer. Source: [`index.html`](index.html) (static HTML; preview images in `assets/img/`). The
three pages share a top bar ("← Inicio" + next entry) so they read as a series.

**[▶ How AD works inside](https://jorgearma.github.io/nordwind-ad-lab/fundamentos.html)** — nobody
attacks anything. It follows one user from logon to opening a share and breaks down Kerberos (KDC,
AS/TGS/AP exchanges, TGT, service tickets, PAC), AGDLP, the access check, ACL inheritance and
AdminSDHolder/SDProp, linking each mechanism to the attack step that abuses it. Terminal output is
reconstructed and `FS01` is illustrative (the `DL_FS01_*` groups exist in the lab, the server does
not). Source: [`fundamentos.html`](fundamentos.html).

**[▶ Watch the attack replay](https://jorgearma.github.io/nordwind-ad-lab/ataque.html)** — an
animated, step-by-step reproduction of the Phase 3 chain (domain graph + terminal + Kerberos
message breakdown), with *why it works*, *how to fix it* and *how to detect it* for every step.
It is a replay of the real attack on this lab, not a live AD in the browser; terminal output
is reconstructed from the writeup with hashes redacted. Source: [`ataque.html`](ataque.html).

Both animated pages share one stylesheet and one playback engine
([`assets/lab.css`](assets/lab.css), [`assets/engine.js`](assets/engine.js)); each page only holds
its own data (nodes, info cards, scenes) and drawing code. No build step, no dependencies; content
in Spanish.

## Scenario

**Nordwind Logistics** — a fictional logistics company. A realistic domain environment
(`nordwind.local`) with its OU structure, users, groups (**AGDLP** model) and GPOs.

## The 3 phases

| Phase | What | Status |
|-------|------|--------|
| 1. **Build** | Stand up a clean AD (DC + client), understanding every step | ✅ Done |
| 2. **Sabotage** | Deliberately introduce misconfigurations (SPN, AS-REP, ACLs) | ✅ Done |
| 3. **Attack** | Enumeration and exploitation (Kerberoasting, AS-REP, BloodHound → Domain Admin) | ✅ Done |

> **Outcome:** starting from **zero credentials**, the attack chain reaches **Domain Admin**
> and a full **DCSync** (krbtgt + Administrator), using only manual, OSCP-friendly tooling —
> no Metasploit. The whole path is written up in [`docs/phase3-attack.md`](docs/phase3-attack.md).

## Stack

- **Hypervisor:** VirtualBox 7 (isolated internal network `NordwindLAN`)
- **DC01:** Windows Server 2022 Standard (AD DS, DNS, DHCP) — `192.168.10.10`
- **CL01:** Windows 11 Enterprise — domain client
- **Automation:** PowerShell 5.1

## Documentation

- [`docs/build-log.md`](docs/build-log.md) — Phase 1: step-by-step build log
- [`scripts/build/`](scripts/build/) — provisioning scripts to stand up the clean domain (+ `reset-to-clean.ps1` to re-arm the lab after an attack). See its [README](scripts/build/README.md) for run order and rationale.
- [`docs/phase2-sabotage.md`](docs/phase2-sabotage.md) — Phase 2: the planted misconfigurations (+ sabotage scripts in [`scripts/`](scripts/))
- [`docs/phase3-attack.md`](docs/phase3-attack.md) — Phase 3: full attack chain, zero credentials → Domain Admin → DCSync
- [`docs/ad-from-the-attacker-side.md`](docs/ad-from-the-attacker-side.md) — **learning walkthrough**: understand AD from the pentest side (build → break → understand), built on this lab
- [`diagrams/`](diagrams/) — interactive HTML visuals of the domain (open in a browser)

> The interactive visuals are written in Spanish (personal study material); an English
> translation is pending.

---

## Credits

The infrastructure base — fictional company design, AGDLP structure and the
provisioning scripts in [`scripts/build/`](scripts/build/) (`01`–`05` + `employees.csv`) —
is from **Maciej Stawowy's lab**
([maciej-stawowy/active-directory-lab](https://github.com/maciej-stawowy/active-directory-lab),
MIT license), vendored unmodified with attribution preserved.

The offensive layer is my own: the Phase 2 sabotage scripts, the Phase 3 attack chain
and documentation, and `scripts/build/reset-to-clean.ps1` (re-arming the lab after an
attack — no upstream equivalent).
