# Nordwind Logistics — Active Directory Lab

An **Active Directory** lab built from scratch, documenting the whole process end to end:
from infrastructure design to offensive exploitation.

Learning and portfolio project — **Jorge Escobar** (OSCP / CRTP preparation).

---

## Scenario

**Nordwind Logistics** — a fictional logistics company. A realistic domain environment
(`nordwind.local`) with its OU structure, users, groups (**AGDLP** model) and GPOs.

## The 3 phases

| Phase | What | Status |
|-------|------|--------|
| 1. **Build** | Stand up a clean AD (DC + client), understanding every step | ✅ Done |
| 2. **Sabotage** | Deliberately introduce misconfigurations (SPN, AS-REP, ACLs) | ⬜ Pending |
| 3. **Attack** | Enumeration and exploitation (Kerberoasting, AS-REP, BloodHound → Domain Admin) | ⬜ Pending |

## Stack

- **Hypervisor:** VirtualBox 7 (isolated internal network `NordwindLAN`)
- **DC01:** Windows Server 2022 Standard (AD DS, DNS, DHCP) — `192.168.10.10`
- **CL01:** Windows 11 Enterprise — domain client
- **Automation:** PowerShell 5.1

## Documentation

- [`docs/build-log.md`](docs/build-log.md) — step-by-step build log
- [`diagrams/`](diagrams/) — interactive HTML visuals of the domain (open in a browser)

> The interactive visuals are written in Spanish (personal study material); an English
> translation is pending.

---

## Credits

The infrastructure base (fictional company design, AGDLP structure and provisioning
scripts) is **adapted from Maciej Stawowy's lab**
([maciej-stawowy/active-directory-lab](https://github.com/maciej-stawowy/active-directory-lab),
MIT license). The offensive layer (phases 2 and 3) and the attack documentation are my own.
