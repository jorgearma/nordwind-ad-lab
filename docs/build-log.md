# Build Log — Nordwind AD Lab

> Build journal. Rule: build → inspect → explain → move on.

## 2026-10-15 — Day 1
- Lab design defined (network `192.168.10.0/24`, domain `nordwind.local`).
- Repository initialized.
- DC01 VM created in VirtualBox: 4 GB RAM, 2 vCPU, 60 GB disk, Internal Network
  `NordwindLAN`, Windows Server 2022 ISO mounted. Manual install (no unattended setup).

### Incident #1 — VirtualBox won't start any VM (kernel driver)
- **Symptom:** starting a VM failed with `VERR_VM_DRIVER_NOT_INSTALLED`;
  `sudo /sbin/vboxconfig` failed while compiling the modules.
- **Diagnosis:** read `/var/log/vbox-setup.log`. The real `modpost` error was:
  `module vboxdrv uses symbol cr4_update_irqsoff from namespace module:kvm ... but does not import it`.
  The current kernel (**7.0.0-38**) restricts the symbols `cr4_update_irqsoff`,
  `cr4_read_shadow` and `__flush_tlb_all` to the KVM namespace → VirtualBox
  (out-of-tree) cannot use them.
- **Verification:** compared `Module.symvers` across both kernels. On **6.17.0-40**
  those symbols have no namespace restriction → it compiles there.
- **Solution:** boot the 6.17.0-40 kernel (GRUB → Advanced options) and recompile
  with `sudo /sbin/vboxconfig`. (Kernel pinning for third-party module compatibility.)
- **Next:** install Windows Server 2022 on DC01 (Stage 1).

## 2026-10-16/17 — Day 2: Domain is alive (Phase 1 complete)

From an empty Server VM to a working domain with a client joined and
authenticating over Kerberos. **Phase 1 (Build) closed.**

### What was built
- **DC01 promoted** to a new forest: domain `nordwind.local` (NetBIOS `NORDWIND`),
  with the DC acting as DNS. Clients sit on an isolated Internal Network
  (`NordwindLAN`) and point their DNS to the DC at `192.168.10.10` — without this,
  domain resolution and the join simply fail.
- **OU structure** created by hand (to understand the design before scripting it).
- **10 domain users** and **14 groups** following the **AGDLP** model
  (Accounts → Global → Domain Local → Permissions).
- **CL01 (Windows 11)** joined to `nordwind.local`, logged in as a domain user,
  with a **Kerberos TGT confirmed via `klist`**.

### Concepts consolidated (main AD gap, now closed)
LDAP as the directory's query language · Kerberos/KDC flow (TGT → TGS) ·
AGDLP group nesting · OUs vs groups (resources are granted through groups,
authority is delegated through OUs) · SID/RID. Detailed notes in my Obsidian
vault; diagrams to be exported into `diagrams/`.

### Incident #2 — Valid credentials rejected at logon (Kerberos clock skew)
- **Symptom:** a correct username/password was rejected when logging CL01 into
  the domain.
- **Diagnosis:** Kerberos refuses authentication when the client and KDC clocks
  differ by more than **5 minutes** (`KRB_AP_ERR_SKEW`) — a replay-protection
  measure, not a credential problem. CL01's clock had drifted.
- **Fix:** sync CL01's time/timezone to DC01; logon succeeded. Credentials were
  independently confirmed with `ValidateCredentials()` to rule out the password
  before chasing the clock.

### Next
Phase 2 (Sabotage): snapshot the clean lab, then plant a Kerberoastable SPN
(`svc_sql`), an AS-REP-roastable account, and an abusable ACL for BloodHound.
