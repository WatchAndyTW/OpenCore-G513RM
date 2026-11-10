# RyzenHV review

Source review of [RyzenHV](https://github.com/OverlordDev/ryzen-hypervisor.framework) before loading it on this
machine, to run Docker Desktop. Read-only: nothing was built or run. Reviewed 2026-11-09 at `v0.7.9-beta`
(`99627c6`), checked out in `third_party/ryzenhv/` (git-ignored). Line numbers refer to that commit.

Machine: Ryzen 9 6900HX, macOS 26.7.2, Docker Desktop 4.99.0 (build 245822). The author tested only a Ryzen 7 5800H on
macOS 15.8.1 with Docker Desktop 4.97.0; one user reported Parallels working on 26.7.1.

## How Docker would run

- **Shim mode** (boot-args `rhv_enable_svm=1 rhv_allow_users=1`): wrapper scripts in Docker.app inject
  `libryzenhv.dylib` into HyperKit and the backend with `DYLD_INSERT_LIBRARIES`. The shim talks to the kext's
  IOUserClient. Needs AMFI relaxed (`amfi_get_out_of_my_way=0x1`, already set here).
- **Native mode** (adds `rhv_hv=1`): the kext evicts Apple's hypervisor traps and registers its own through xnu's
  `hv_set_traps` / `hv_set_callbacks`, then sets `kern.hv_support` to 1. Docker.app stays unmodified.

The kext never patches kernel code. The only direct kernel-data write is the `kern.hv_support` int, and that code is
careful: it decodes the address from `hv_get_support`, refuses on an unknown byte pattern, verifies the write and
reverts it (`HvFrontend.cpp:1464-1538`). The HyperKit CPU-vendor and GLA checks are patched in HyperKit's own memory,
only when the byte pattern occurs exactly once. The repo has no binaries, telemetry, obfuscation or hidden selectors.

## Findings

Verified means read end to end in the kext. Impact claims that depend on xnu or CPU behaviour were not tested.

| # | Severity | Finding | Where |
|---|---|---|---|
| 1 | Critical | **Read-only memory made writable.** A range that can only be pinned for reading is mapped without W, but `VmProtect` adds W back: `protect()` ignores `Backing::dir`. A guest can then write the page-cache page of a file the user can only read (e.g. root-owned config), a likely root escalation. Added in 0.7.9-beta; 0.7.8 refuses such ranges. | `Vm.cpp:315-329`, `Vm.cpp:460-483`, `Npt.hpp:227-238` |
| 2 | High | **`rhv_allow_users=1` makes every console-user process admin.** That includes VM creation and the HvControl commands: `hv mode 1` (native mode at runtime, no `rhv_hv` needed), `hv sysctl 1`, SVM limit, guest-memory dumps. Opening the client is unrestricted: no entitlement or code-signing check. | `RyzenHVUserClient.cpp:25-35, 247-284` |
| 3 | High | **Native mode: no caller check, use-after-free races.** Trap handlers check no entitlement or uid, so any process of any uid can create VMs. `tVmDestroy` frees the VM with no refcount while other threads of the process can be inside `tVcpuCreate`/`tVmMap`/`tVmUnmap`/`tVmProtect`/`tVmSyncTsc`. | `HvFrontend.cpp:364-442, 1316-1340, 724` |
| 4 | High | **Root daemon can be hijacked.** `rhv autostart install` runs `/usr/local/libexec/ryzenhv/hv-sysctl.sh` as root at boot, but `/usr/local` is owned by the user here, so any user process can swap the script. | `scripts/hv-sysctl-daemon.sh:21, 42-44, 96` |
| 5 | High | **Shim injected into Docker's whole process tree.** The backend wrapper is Docker.app's main executable and exports `DYLD_INSERT_LIBRARIES`; nothing unsets it, so every child (Electron UI, helpers, CLI plugins) loads the shim from user-writable `~/.ryzenhv/lib`. | `scripts/docker-desktop-shim.sh:95-100`, `shim/hv_shim.c:102-147` |
| 6 | High | **Raw-mode guest can panic the host.** Raw VMs don't intercept XSETBV and XCR0 is restored only when it differs from the starting value, so the kext's own XRSTOR can #GP with interrupts off. Docker (VMX mode) doesn't use raw mode, but any allowed user can. | `Vm.cpp:676-677, 976-1033` |
| 7 | Medium | `rhv docker-desktop get` downloads Docker without a checksum, uses `hdiutil -noverify`, only displays the signature, and `rm -rf`s the installed app. It would downgrade 4.99.0 to 4.97.0. | `release/rhv:434-443` |
| 8 | Medium | No limits: unlimited wired memory via VmMap; VmUnmap of up to 2^48 bytes walks every page under a write lock (unkillable); 16 global VM slots. #AC/#DB/#MC not force-intercepted. | `Vm.cpp:93, 377-458, 669` |
| 9 | Medium | `rhv kext` mounts every EFI partition and edits the live ESP (the app does it as root with no prompt), so this repo would drift. Plist editing itself is careful (PlistBuddy, backup, lint). | `release/rhv:125-211`, `app/.../Model.swift:185-196` |
| 10 | Medium | Native-mode layouts (`hv_callbacks_t`, trap indices, shared-page offsets) were reverse-engineered on Sequoia. A changed callbacks struct on Tahoe would panic. | `HvFrontend.cpp:29-38, 115-123` |
| 11 | Low | The log, readable by any process, leaks the kernel address of `hv_support_available` (KASLR), VMCB/NPT physical addresses, other processes' addresses and guest memory dumps. | `RyzenHVUserClient.cpp:215-232`, `HvFrontend.cpp:1484` |
| 12 | Low | `/tmp/rhv-debug` etc., which any account can create, switch HyperKit tracing on; no RSB stuffing/IBPB on VM exit; raw mode doesn't restore host DR7. | `shim/hv_shim.c:116, 556, 599`, `SvmRun.S:91-130` |

Done carefully (verified): selector bounds and fixed struct sizes for every method; VMCS writes can't reach VMCB
pointer fields; I/O and MSR intercepts are all-ones (no path to EFER, VM_HSAVE_PA, VM_CR or SPEC_CTRL); the world switch
saves and restores host GS/KERNEL_GS_BASE/TR/LDTR before GIF=1; NPT maps check overflow, alignment and overlap and roll
back; VMs are bound to the owning task; per-CPU HSAVE is re-checked before every VMRUN; unload is blocked while clients
exist; `-rhv_off` disables everything.

## Verdict

Patches 1-4 below and the ReadLog restriction are in `src/ryzenhv/g513rm-fixes.patch`; setup is in [ryzenhv.md](ryzenhv.md).

Not safe to load as published. With `rhv_allow_users=1` (which Docker needs in shim mode), any program the user runs
gets a ring-0 attack surface that includes finding 1 (0.7.9-beta) and the native-mode switch (finding 2). Native mode
widens this to every uid (finding 3) for no Docker benefit.

The least risky route is **shim mode, built from source, with local patches**:

1. Make `VmProtect` never grant W on a backing pinned for reading (or build v0.7.8, which lacks the fallback).
2. Gate every HvControl command except Get on real root (`kIOClientPrivilegeAdministrator`), regardless of
   `rhv_allow_users`, so native mode can't be switched on at runtime.
3. `unsetenv("DYLD_INSERT_LIBRARIES")` in the shim's constructor, and only inject into HyperKit and the backend.
   (As built: the backend's own processes keep it, because Docker 4.99 runs the hypervisor check in the backend's
   `services` child; see ryzenhv.md.)
4. Intercept XSETBV in raw mode and restore XCR0 unconditionally after VMRUN.
5. Optional: restrict ReadLog to admin; cap VmUnmap/VmMap sizes.

Then add the kext to this repo's `EFI/` by hand (not `rhv kext`), try it from a USB EFI first, keep Docker 4.99.0
(don't run `rhv docker-desktop get`), and don't install `rhv autostart` (shim mode doesn't need `kern.hv_support`).

Even patched, any process of the console user can still create VMs through an experimental ring-0 component. That is
inherent to the design and acceptable only on a single-user machine.

Not verified: whether the 4.99.0 HyperKit patch patterns match (a reviewer's scan says each occurs exactly once at file
offsets 0x227b45 and 0x20af2d); behaviour on Tahoe at all.
