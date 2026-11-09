# ASUS ROG Strix G15 (G513RM) – macOS Tahoe OpenCore EFI

OpenCore EFI for the **ASUS ROG Strix G15 G513RM** running **macOS Tahoe 26** (tested on 26.7.2), with native-menu
Wi-Fi on the MediaTek MT7922, Bluetooth, the NullMoth NVIDIA driver and a one-click installer.

> Use at your own risk and keep a backup of your data. The installer backs up your current EFI before writing,
> and `--restore` puts it back.

## Hardware

| Part | This laptop |
|---|---|
| Model | ASUS ROG Strix G15 G513RM (BIOS G513RM.327) |
| CPU | AMD Ryzen 9 6900HX (8 cores, Rembrandt) |
| GPU | NVIDIA RTX 3060 Laptop 6 GB (NullMoth driver) · Radeon 680M (no macOS driver, idle) |
| Wi-Fi / Bluetooth | MediaTek MT7922 (AMD RZ616), PCI 14c3:7922 / USB 13d3:3568 |
| Audio | Realtek ALC294 |
| Touchpad | ELAN 04F3:319B, I2C-HID |
| Ethernet | Realtek RTL8125 2.5 GbE |
| SMBIOS | MacBookPro16,4 |
| OpenCore | 1.0.8 RELEASE build |

## What's in the EFI

| Function | Kexts / settings |
|---|---|
| Base | Lilu, VirtualSMC, SMCBatteryManager, ECEnabler, RestrictEvents, NVMeFix, AMD_Vanilla kernel patches (8 cores) + Tahoe 26.4+ time-panic fix |
| CPU power management, sensors | AMDRyzenCPUPowerManagement + SMCAMDProcessor 0.7.2f1 |
| Wi-Fi | AirportMtkWlan 1.5.0 (SimpleMtkWlan) + this repo's fixes: WPA2-Enterprise / eduroam, warm-reboot / standby-power recovery ([docs/wifi.md](docs/wifi.md)) |
| Bluetooth | BlueToolFixup + SimpleMtkBtFw / SimpleMtkBtPatcher 1.1.0 |
| Keyboard, touchpad | VoodooPS2Controller (keyboard only), VoodooI2C + VoodooI2CHID |
| ASUS keys, fans, backlight, brightness | AsusSMC, BrightnessKeys, SSDT-PNLF |
| Audio | VoodooHDA 3.7.1 (AppleHDA blocked, AZAL→HDAS rename) |
| USB | USBToolBox + G513RM map (keyboard, Bluetooth, 2× USB-A, 2× USB-C), XHCILagFix + USBXHCIWakeup (Ryzen 6000 USB lag) |
| Ethernet | LucyRTL8125Ethernet |
| NVIDIA | AMFIPass, boot-args and csr-active-config for the NullMoth driver; IONDRVSupport excluded (dGPU/MUX panel mode) |
| Boot picker | OpenCanopy (GoldenGate theme) |
| Docker Desktop (experimental, test on USB first) | RyzenHV 0.7.9-beta + this repo's security fixes: Hypervisor.framework on AMD SVM ([docs/ryzenhv.md](docs/ryzenhv.md)) |

How each setting was chosen: [docs/config-notes.md](docs/config-notes.md).

## Known issues

- **Radeon 680M**: no macOS driver.
- **AirDrop, Sidecar, Continuity**: not supported by the MT7922 driver.
- **Wi-Fi missing after a restart or shutdown** (the M.2 card keeps standby power, so the chip isn't reset): the
  bundled driver build (v4) no longer uses the chip's broken PCIe FLR and leaves the chip in a clean state at shutdown.
  Not yet confirmed on this laptop. Install the log agent (`sh tools/mtklog-autosave.sh --install`) so a failed boot
  leaves a log, and see [docs/wifi.md](docs/wifi.md).
- **Troubleshooting a boot problem**: the EFI uses the RELEASE build of OpenCore, which logs almost nothing. To get a
  boot log, swap in the DEBUG build of OpenCore 1.0.8 (OpenCore.efi, BOOTx64.efi, Drivers) and set `Misc > Debug > Target`
  to 67, which writes `opencore-*.txt` to the EFI partition.

## BIOS settings

| Setting | Value |
|---|---|
| Secure Boot | Off |
| CSM | Off |
| Fast Boot | Off |
| Above 4G Decoding | On |
| GPU mode | dGPU (MUX), as this config is set up. For hybrid mode see [NVIDIA](#nvidia-driver) |

In Windows, also turn off **Fast Startup** (Control Panel → Power Options → "Choose what the power buttons do").
Otherwise Windows hibernates instead of shutting down and leaves the Wi-Fi card half-initialised.

## Install / update

### From macOS: one click

1. Download or clone this repo.
2. Double-click **`Install.command`**. If macOS blocks it, right-click it → **Open** → **Open**.
3. Enter your password. The installer:
   - checks this is a G513RM (Ryzen 6000 + MT7922),
   - finds the EFI partition that holds OpenCore and mounts it,
   - keeps your serial numbers (SystemSerialNumber, MLB, SystemUUID, ROM) from the installed config. The repo only
     has placeholders, and a first install generates new ones,
   - validates the new `config.plist` with `ocvalidate`,
   - lists what will change and asks before writing,
   - saves the current `EFI/OC` to `EFI/OC-backup` on the EFI partition and to `~/G513RM-EFI-backups/`,
   - replaces only `EFI/OC`. `EFI/BOOT` is written only if the partition has none, so Pop!_OS and Windows on the
     same EFI partition are not affected.
4. Reboot.

Terminal equivalent: `sudo bash scripts/install.sh`. Add `--dry-run` to only see what would change.

### From Linux (Pop!_OS etc.)

```sh
sudo bash scripts/install.sh            # EFI partition mounted at /boot/efi
sudo bash scripts/install.sh --esp /dev/nvme0n1p1   # or name it
```

On Linux the installer also adds an "OpenCore" firmware boot entry if there isn't one, keeping your current boot
order first. Pick OpenCore with **F8** at power-on, or move it up in the BIOS.

### If it doesn't boot

Boot the other OS (or an older OpenCore from F8) and run:

```sh
sudo bash scripts/install.sh --restore   # swaps EFI/OC and EFI/OC-backup; run again to swap back
```

Dated copies of each replaced EFI are also in `~/G513RM-EFI-backups/` (on the OS you installed from).

## NVIDIA driver

The NullMoth driver (via the 1401 project) installs into `/Library/Extensions` from macOS, not into the EFI.
This EFI already has the boot-args, `csr-active-config` and AMFIPass it needs.

Don't let the 1401 Mac app edit OpenCore on this laptop. Its USB map drops the internal keyboard, and its
built-in-screen check only knows Intel iGPUs. Install the driver by hand instead (`sudo ./install.sh` from the
release tarball).

To switch the panel between hybrid mode (680M) and dGPU/MUX mode, run from Linux:
`sudo bash tools/nvidia-oc-config.sh --panel hybrid|dgpu` (also `--off` / `--on` / `--revert`; `--dry` previews).

## Repo layout

```
Install.command          double-click installer (macOS)
EFI/                     the OpenCore EFI (serials are placeholders)
scripts/install.sh       installer used by Install.command; also runs on Linux
tools/
  wifi-verify.sh         Wi-Fi join timeline (802.1X key events, IPv4) from the system log
  mtklog.sh              the Wi-Fi driver's own log (works even when the driver failed to start)
  mtklog-autosave.sh     login agent that saves that log every boot, so a failed boot can be diagnosed later
  nvidia-oc-config.sh    Linux: NVIDIA settings / panel mode in the installed config
  bin/                   ocvalidate, macserial (OpenCore 1.0.8 utilities) for macOS and Linux
src/
  acpi/                  SSDT sources (CPUR, EC-USBX, PNLF)
  usbmap/make_utbmap.py  generates the USB map
  wifi/                  driver patch, MT7922 firmware, build.sh (rebuilds AirportMtkWlan.kext)
  ryzenhv/               security fixes, build.sh (rebuilds RyzenHV.kext and the Docker shim)
docs/                    config notes, Wi-Fi driver notes, RyzenHV setup and review
```

## Credits

- [acidanthera](https://github.com/acidanthera): OpenCore, Lilu, VirtualSMC, RestrictEvents, NVMeFix, BlueToolFixup, BrightnessKeys, VoodooPS2
- [AMD OS X](https://github.com/AMD-OSX/AMD_Vanilla): AMD kernel patches · [trulyspinach](https://github.com/trulyspinach/SMCAMDProcessor): AMD CPU power management
- [flxxxxddd](https://github.com/flxxxxddd): SimpleMtkWlan / SimpleMtkBtFw (MT7922 Wi-Fi and Bluetooth), with laobamac and pengubow's work
- [VoodooI2C](https://github.com/VoodooI2C), [hieplpvip](https://github.com/hieplpvip) (AsusSMC), [1Revenger1](https://github.com/1Revenger1) (ECEnabler), [dhinakg](https://github.com/dhinakg) (USBToolBox, AMFIPass), Mieze/Lucy (RTL8125), VoodooHDA
- NullMoth / 1401: NVIDIA driver
- [Xelon233/ROG-G15-Series-OpenCore](https://github.com/Xelon233/ROG-G15-Series-OpenCore): reference G513RM EFI (XHCI lag fix, USB wake, extras)

Third-party licences: [NOTICE.md](NOTICE.md).
