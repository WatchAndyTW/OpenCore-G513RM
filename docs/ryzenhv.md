# RyzenHV: Docker Desktop on this laptop

macOS's Hypervisor.framework needs Intel VT-x, so on the 6900HX `kern.hv_support` is 0 and Docker Desktop stops with
"Hypervisor check failed". RyzenHV is a kext that provides the same API on AMD's SVM. Docker's HyperKit uses it through
a small library (the shim) loaded into HyperKit and Docker's backend.

**Status: experimental, not yet booted on this laptop.** The author tested a Ryzen 7 5800H on macOS 15.8.1 only. A
kernel bug here is a panic, so test it from a USB EFI first (below). Why it is set up this way, and what was patched:
[ryzenhv-review.md](ryzenhv-review.md).

## What's in the EFI

- `EFI/OC/Kexts/RyzenHV.kext`: built by `bash src/ryzenhv/build.sh` from v0.7.9-beta plus `src/ryzenhv/g513rm-fixes.patch`.
  The `Kernel > Add` entry is limited to Tahoe (MinKernel 25.0.0, MaxKernel 25.99.99).
- boot-args `rhv_enable_svm=1` (switch SVM on, on every core) and `rhv_allow_users=1` (your account may run VMs;
  HyperKit runs as you). `amfi_get_out_of_my_way=0x1`, which the shim needs, was already there for the NVIDIA driver.
- **Not** `rhv_hv=1` (native mode). It replaces Apple's hypervisor hooks in the kernel, lets every process on the
  machine create VMs, and isn't needed for Docker. The patch makes it root-only even at runtime.

## 1. Test boot from a USB stick

The internal EFI stays untouched, so if the kext panics you just boot without the USB stick.

1. Format a USB stick as **GUID Partition Map + MS-DOS (FAT)** in Disk Utility. Find its EFI partition with
   `diskutil list external` (e.g. `disk4s1`).
2. Copy your installed EFI to it first, so the installer keeps your serial numbers (on an empty partition it would
   generate new ones):
   ```bash
   sudo diskutil mount disk0s1          # your internal EFI partition; check with: diskutil list internal
   sudo diskutil mount disk4s1          # the USB stick's EFI partition
   sudo cp -RX /Volumes/EFI/EFI "/Volumes/EFI 1/"   # check which mount point is which with: diskutil info disk4s1
   ```
3. Install this repo's EFI on the stick: `sudo bash scripts/install.sh --esp disk4s1`. Check that the summary says
   `+ RyzenHV.kext (new)` and the boot-args gain `rhv_enable_svm=1 rhv_allow_users=1`.
4. Restart, press **F8** and boot the USB stick.

If it panics or hangs: hold the power button, then boot normally (internal EFI, no kext).

## 2. Check the kext

```bash
R=~/macOS-G513RM/build/ryzenhv/build
$R/rhv-info               # CPU / SVM state: SVM should be on for all 16 CPUs
$R/rhv-info log           # the kext's own log
sudo $R/rhv-info selftest # EFER.SVME and VM_HSAVE_PA on every core
```

`kern.hv_support` stays 0 in this setup. That's expected: only the processes that load the shim see 1.

## 3. Docker Desktop

Docker 4.99.0 (build 245822) is fine; both HyperKit code patterns were checked against it. Don't run `rhv docker-desktop get`,
which would replace it with 4.97.0.

1. Turn off automatic updates: Docker Desktop > Settings > Software updates. An update replaces the app and undoes step 3.
2. Quit Docker Desktop and back up its settings:
   `cp ~/Library/Group\ Containers/group.com.docker/settings-store.json ~/settings-store.json.bak`
3. `~/macOS-G513RM/build/ryzenhv/scripts/docker-desktop-shim.sh install`

   This wraps `com.docker.hyperkit` and `com.docker.backend` in Docker.app (Docker's originals are kept as `.orig` / `.real`),
   copies the shim to `~/.ryzenhv/lib/`, and sets `UseVirtualizationFramework` to false so Docker uses HyperKit.
4. Start Docker, then `docker run --rm hello-world`.

If it fails: `~/.ryzenhv/hyperkit.log`, `$R/rhv-info log`, and
`~/Library/Containers/com.docker.docker/Data/log/host/com.docker.backend.log`.

## 4. Make it permanent

Once Docker works and the laptop is stable (including a sleep/wake), install the EFI as usual: `sudo bash scripts/install.sh`.

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
