# Build scripts — standing up the clean domain

These scripts provision the **healthy** `nordwind.local` domain: the baseline that
Phase 2 later sabotages and Phase 3 attacks. Run them on **DC01**, in an **elevated**
PowerShell session, with the AD DS role already installed and the forest promoted
(see [`../../docs/build-log.md`](../../docs/build-log.md)).

## Provenance & attribution

Scripts `01`–`05` and `data/employees.csv` are **vendored unmodified** from
[maciej-stawowy/active-directory-lab](https://github.com/maciej-stawowy/active-directory-lab)
(MIT License — a copy is kept here as [`LICENSE-maciej-stawowy`](LICENSE-maciej-stawowy)).
They stand up the base company (OUs, users, AGDLP groups) that the design is built on.

What is **mine** in this folder is this README (the rationale below) and
[`reset-to-clean.ps1`](reset-to-clean.ps1) — the offensive layer's cleanup counterpart,
which has no upstream equivalent because the base lab has no attack phase.

## Run order

| # | Script | What it does | Why it runs here |
|---|--------|--------------|------------------|
| 1 | `01-create-ou-structure.ps1` | Builds the OU tree (`Nordwind` → `_Admins`, `Users/<dept>`, `Computers`, `Groups`, `ServiceAccounts`). | OUs are **containers for delegation**; everything else needs a place to live first. |
| 2 | `02-create-users.ps1` | Bulk-creates the 10 employees from `data/employees.csv`, each in their department OU. Writes a `lab_passwords.csv`. | The **A** (Accounts) of AGDLP. Needs the OUs from step 1. |
| 3 | `03-create-groups-agdlp.ps1` | Creates 7 Global groups (`G_<dept>_Users`) and 7 Domain Local groups (`DL_FS01_<resource>_<perm>`). | The **G** and **DL** scaffolding. Must exist before anything can be nested into it. |
| 4 | `04-add-users-to-groups.ps1` | Adds users to their Global group, then nests each Global into its Domain Local. | The **A→G→DL** wiring — the part that makes BloodHound paths meaningful later. |
| 5 | `05-cl01-prepare-and-join.ps1` | Prepares CL01 (Win11) and joins it to the domain. | Run **on CL01**, not DC01 — gives the lab a realistic member workstation. |

### Prerequisites

- `data/employees.csv` copied to `C:\LabFiles\` on DC01 (script 02 reads it from there).
- Forest `nordwind.local` already promoted; DC01 is its own DNS at `192.168.10.10`.
- The top-level `Nordwind` OU: script 01 creates it if missing (it was made via GUI in my build for a screenshot — see build-log).

## Why AGDLP (the one concept worth defending in an interview)

**A**ccounts → **G**lobal groups → **D**omain **L**ocal groups → **P**ermissions.

- Users go into a **Global** group *by role* (`G_Sales_Users`).
- That Global group is nested into a **Domain Local** group *by resource*
  (`DL_FS01_Sales_Modify`).
- Permissions are assigned **only** on the Domain Local group — never on the user,
  never on the Global group.

The payoff: onboarding a new hire is **one** group membership, with zero ACL edits
across the file tree. And from the attacker's side, this is exactly why group nesting
turns into *attack paths* in BloodHound — control over a role group transitively grants
whatever its resource groups can reach.

## `reset-to-clean.ps1` — re-arming the lab (mine)

After Phase 3 you have a wrecked domain (an extra Domain Admin, a Kerberoastable
service account, an AS-REP-roastable user, planted ACEs). Instead of rebuilding the
VMs from zero, this script reverts the three sabotages in safe order
(ACLs/membership → pre-auth → SPN/account) and verifies the result, so you can snapshot
a clean state and re-attack on demand.

> One caveat it documents but does **not** auto-fix: a full DCSync exposed the `krbtgt`
> hash (Golden Ticket persistence). Properly evicting that means a double `krbtgt`
> reset; in this single-DC lab a VM snapshot restore is the cleaner fix for that one
> concern. See the note at the bottom of the script.
