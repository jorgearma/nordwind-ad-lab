# Build Log — Nordwind AD Lab

> Bitácora del montaje. Regla: construir → inspeccionar → explicar → avanzar.

## 2026-10-15 — Día 1
- Diseño del laboratorio definido (red `192.168.10.0/24`, dominio `nordwind.local`).
- Repositorio inicializado.
- VM DC01 creada en VirtualBox: 4 GB RAM, 2 vCPU, disco 60 GB, red interna `NordwindLAN`,
  ISO de Windows Server 2022 montado. Instalación manual (sin desatendido).

### Incidente #1 — VirtualBox no arranca ninguna VM (driver del kernel)
- **Síntoma:** al iniciar una VM, error `VERR_VM_DRIVER_NOT_INSTALLED`; `sudo /sbin/vboxconfig`
  fallaba al compilar los módulos.
- **Diagnóstico:** leído `/var/log/vbox-setup.log`. Error real de `modpost`:
  `module vboxdrv uses symbol cr4_update_irqsoff from namespace module:kvm ... but does not import it`.
  El kernel actual (**7.0.0-38**) restringe los símbolos `cr4_update_irqsoff`, `cr4_read_shadow`
  y `__flush_tlb_all` al namespace de KVM → VirtualBox (out-of-tree) no puede usarlos.
- **Verificación:** comparado `Module.symvers` de ambos kernels. En **6.17.0-40** esos símbolos
  NO tienen restricción de namespace → ahí sí compila.
- **Solución:** arrancar con el kernel 6.17.0-40 (GRUB → Advanced options) y recompilar con
  `sudo /sbin/vboxconfig`. (Kernel pinning por compatibilidad de módulo de terceros.)
- **Siguiente:** instalar Windows Server 2022 en DC01 (Stage 1).
