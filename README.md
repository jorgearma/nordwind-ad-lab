# Nordwind Logistics — Active Directory Lab

Laboratorio de **Active Directory** construido desde cero, documentando el proceso de
principio a fin: desde el diseño de la infraestructura hasta la explotación ofensiva.

Proyecto de aprendizaje y portfolio — **Jorge Escobar** (preparación OSCP / CRTP).

---

## Escenario

**Nordwind Logistics** — empresa ficticia de logística. Entorno de dominio realista
(`nordwind.local`) con su estructura de OUs, usuarios, grupos (modelo **AGDLP**) y GPOs.

## Las 3 fases

| Fase | Qué | Estado |
|------|-----|--------|
| 1. **Construir** | Montar el AD sano (DC + cliente), entendiendo cada paso | 🟡 En curso |
| 2. **Sabotear** | Introducir deliberadamente malas configuraciones (SPN, AS-REP, ACLs) | ⬜ Pendiente |
| 3. **Atacar** | Enumeración y explotación (Kerberoasting, AS-REP, BloodHound → Domain Admin) | ⬜ Pendiente |

## Stack

- **Hipervisor:** VirtualBox 7 (red interna aislada `NordwindLAN`)
- **DC01:** Windows Server 2022 Standard (AD DS, DNS, DHCP) — `192.168.10.10`
- **CL01:** Windows 11 Enterprise — cliente de dominio
- **Automatización:** PowerShell 5.1

## Documentación

- [`docs/build-log.md`](docs/build-log.md) — bitácora del montaje, paso a paso

---

## Créditos

La base de infraestructura (diseño de la empresa ficticia, estructura AGDLP y scripts
de aprovisionamiento) está **adaptada del lab de Maciej Stawowy**
([maciej-stawowy/active-directory-lab](https://github.com/maciej-stawowy/active-directory-lab),
licencia MIT). La capa ofensiva (fases 2 y 3) y la documentación de ataque son propias.
