# RyzenHV: Docker Desktop on this laptop

macOS's Hypervisor.framework needs Intel VT-x, so on the 6900HX `kern.hv_support` is 0 and Docker Desktop stops with
"Hypervisor check failed". RyzenHV is a kext that provides the same API on AMD's SVM. Docker's HyperKit uses it through
a small library (the shim) loaded into HyperKit and Docker's backend.

**Status: experimental. Works on this laptop** (macOS 26.7.2, Docker Desktop 4.99.0 build 245822, 2026-11-10):
`docker run hello-world`, 16 vCPUs, 8 GB. Sleep/wake and long runs are not yet tested. A kernel bug here is a panic, so
keep the Pop!_OS fallback below in mind. Why it is set up this way, and what was patched:
[ryzenhv-review.md](ryzenhv-review.md).

## What's in the EFI

- `EFI/OC/Kexts/RyzenHV.kext`: built by `bash src/ryzenhv/build.sh` from v0.7.9-beta plus `src/ryzenhv/g513rm-fixes.patch`.
  The `Kernel > Add` entry is limited to Tahoe (MinKernel 25.0.0, MaxKernel 25.99.99).
- boot-args `rhv_enable_svm=1` (switch SVM on, on every core) and `rhv_allow_users=1` (your account may run VMs;
  HyperKit runs as you). `amfi_get_out_of_my_way=0x1`, which the shim needs, was already there for the NVIDIA driver.
- **Not** `rhv_hv=1` (native mode). It replaces Apple's hypervisor hooks in the kernel, lets every process on the
  machine create VMs, and isn't needed for Docker. The patch makes it root-only even at runtime.

## 1. Install the EFI

```bash
sudo bash scripts/install.sh --dry-run   # should list only + RyzenHV.kext and the two new boot-args
sudo bash scripts/install.sh
```

The installer moves the working `EFI/OC` to `EFI/OC-backup` first. If macOS then panics or hangs at boot
(`debug=0x100` keeps the panic on screen), hold the power button, boot Pop!_OS (F8), and put the old one back:

```bash
findmnt /boot/efi                          # the EFI partition shared with macOS
sudo mv /boot/efi/EFI/OC /boot/efi/EFI/OC-ryzenhv
sudo mv /boot/efi/EFI/OC-backup /boot/efi/EFI/OC
```

(`sudo bash scripts/install.sh --restore` does the same from a clone of this repo.) Check that Pop!_OS boots before
installing. To test from a USB stick instead, copy only `EFI/OC` to the stick's EFI partition (not `EFI/BOOT`, which on
this laptop is Pop!_OS's systemd-boot), then `sudo bash scripts/install.sh --esp diskNs1` and boot it with F8.

## 2. Check the kext

```bash
R=~/macOS-G513RM/build/ryzenhv/build
$R/rhv-info               # CPU / SVM state: SVM should be on for all 16 CPUs
$R/rhv-info log           # the kext's own log
sudo $R/rhv-info selftest # EFER.SVME and VM_HSAVE_PA on every core
DYLD_INSERT_LIBRARIES=$R/libryzenhv.dylib $R/hvf-smoke   # a tiny VM through the shim: ends with PASS
```

`kern.hv_support` stays 0 in this setup. That's expected: only the processes that load the shim see 1.

## 3. Docker Desktop

Docker 4.99.0 (build 245822) works; both HyperKit code patterns match it. Don't run `rhv docker-desktop get`, which
would replace it with 4.97.0.

1. Turn off automatic updates: Docker Desktop > Settings > Software updates. An update replaces the app and undoes step 3.
2. Quit Docker Desktop and back up its settings:
   `cp ~/Library/Group\ Containers/group.com.docker/settings-store.json ~/settings-store.json.bak`
3. `~/macOS-G513RM/build/ryzenhv/scripts/docker-desktop-shim.sh install`

   This wraps `com.docker.hyperkit` and `com.docker.backend` in Docker.app (Docker's originals are kept as `.orig` / `.real`),
   copies the shim to `~/.ryzenhv/lib/`, and sets `EngineTypeMac` to `hyperkit` so Docker uses HyperKit (4.99 ignores
   the older `UseVirtualizationFramework`, which is set too).
4. Start Docker, then `docker run --rm hello-world` (in a new terminal: `~/.docker/bin` is on PATH via `~/.zprofile`).

The backend now logs to `com.docker.backend.real.log` and warns "cannot find executable path" at start; both come from
the wrapper and are harmless.

If it fails: `~/.ryzenhv/hyperkit.log`, `$R/rhv-info log`, and
`~/Library/Containers/com.docker.docker/Data/log/host/com.docker.backend.real.log`. "Hypervisor check failed" means
the backend's `services` process did not get the shim (`vmmap <pid> | grep libryzenhv`). For a trace, create
`~/.ryzenhv/debug` and start Docker with `open -a Docker --env RYZENHV_TRACE=2 --env RYZENHV_TRACE_FILE=/some/file`;
delete `~/.ryzenhv/debug` afterwards (tracing logs guest registers and costs CPU).

## Undo

- Docker: quit it, `~/macOS-G513RM/build/ryzenhv/scripts/docker-desktop-shim.sh uninstall`, `rm -rf ~/.ryzenhv`, and copy
  the settings backup back.
- Kext: set its `Kernel > Add` entry to `Enabled = false` (or remove it and the two boot-args), then reinstall the EFI.
  Booting with `-rhv_off` added to boot-args also leaves the kext doing nothing.

## Don't use

- `rhv kext` / `rhv kext --native` or the RyzenHV app: they edit the live EFI partition directly, not this repo.
- `rhv autostart install`: a root daemon under `/usr/local`, which your account owns, so any program could replace it.
  Only native mode needs it.
- The release archive (prebuilt kext and QEMU); `build.sh` builds from source.

## Still true after the patches

Any program running as you can open the kext and run a VM through it: the kext's VM code is reachable from your
account. That's how Docker uses it, and it is acceptable only because this laptop has one user. Root-only parts
(native mode, `kern.hv_support`, debugging) stay root-only.

The shim is loaded into Docker's backend processes, HyperKit, and the processes the backend starts directly (seen: the
Docker Desktop UI's main process). Those drop it at once, so it goes no further down the tree.
