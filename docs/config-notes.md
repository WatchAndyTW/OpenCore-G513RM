# Config notes

Why `EFI/OC/config.plist` looks the way it does. Everything here was tried on this G513RM.

## Base

- Built from OpenCore 1.0.8 `Sample.plist` and the AMD_Vanilla patch set; RELEASE build since 2026-11-04
  (`Misc > Debug`: Target 3, AppleDebug off, ApplePanic on so kernel panics are still saved to the EFI partition). The four
  `cpuid_cores_per_package` patches are set to **8** cores (6900HX). The byte after the `B8`/`BA` opcode holds the core count.
- **Booter > DevirtualiseMmio = true**: without it boot.efi fails with `EB.MM.AKM Err(0xE)` and then `STOP 0x16`.
- **Booter > ResizeAppleGpuBars = 0** and **UEFI > ResizeGpuBars = -1**: the RTX 3060 BAR1 is 8 GB with Resizable BAR on.
  macOS supports at most 1 GB, and the NVIDIA driver sets up the BAR itself.
- **Booter > DisableVariableWrite = true**: required by the NVIDIA driver on AMD configs that use DevirtualiseMmio.
- **Kernel > Quirks > ProvideCurrentCpuInfo = true** (AMD_Vanilla), **DisableIoMapper = true** (MT7922 Wi-Fi DMA).
- **Kernel > Emulate > DummyPowerManagement = true**.
- Kernel patch **"laobamac | thread_invoke, thread_dispatch | Remove non-monotonic time panic | 26.4+"**: AMD_Vanilla's
  version stops matching on macOS 26.4 and later.
- **PlatformInfo**: `MacBookPro16,4`, `UpdateSMBIOSMode = Create`. Tahoe supports this model, and the reference G513RM EFI
  runs the NVIDIA driver with it. `Custom` mode would write a GUID macOS only reads with CustomSMBIOSGuid (Dell).
- **ACPI**: `SSDT-EC-USBX` creates a fake `EC` under `\_SB.PCI0.SBRG` and leaves the real `EC0` alone, because the
  battery needs it. Dortania's prebuilt uses `LPCB`, which doesn't exist here. `SSDT-CPUR` adds the legacy `Processor`
  objects macOS needs (the firmware only declares ACPI0007 devices under `\_SB.PLTF`, one per thread, 16 in total), and
  `SSDT-PNLF` adds the backlight device for macOS only. Sources are in `src/acpi/`.
- **Misc > Security**: SecureBootModel Disabled (NVIDIA driver), Vault Optional, ScanPolicy 0.

## Keyboard / touchpad

VoodooPS2Controller with only its keyboard plugin; the PS2 trackpad/mouse plugins are off. The touchpad is I2C-HID
(ELAN, `\_SB.I2CA.TPD0`) on VoodooI2C + VoodooI2CHID. The GPIO controller is AMD (`\_SB.GPIO`), so there's no
SSDT-GPI0 and VoodooI2C falls back to polling.

## USB

- `UTBMap.kext` (from `src/usbmap/make_utbmap.py`) maps:
  - XHC0: HS03 internal N-KEY keyboard, HS04 MT7922 Bluetooth
  - XHC1: two USB-A ports (HS01/HS02 + SS01/SS02)
  - XHC3 and XHC4: one USB-C port each (HS01 + SS01)

  UTBDefault is off.
- **XHCILagFix + USBXHCIWakeup** (from the reference G513RM EFI): Ryzen 6000 XHCI controllers lose interrupts under
  macOS. Without these you get multi-second key delays, stuck key repeat and slow USB networking. Their Lilu
  requirement was lowered from 1.7.3 to 1.7.0, and every symbol they use is in Lilu 1.7.2. To turn them off:
  `-xhcilagfixoff`, `-xhciwakeupoff`.

## CPU power management

AMDRyzenCPUPowerManagement + SMCAMDProcessor 0.7.2f1 (trulyspinach release, same binaries as the reference EFI).
They provide P-state control plus CPU temperature and power sensors through VirtualSMC. Load order: Lilu, VirtualSMC,
AMDRyzenCPUPowerManagement, SMCAMDProcessor.

## Extras (taken from the reference G513RM EFI)

- **Audio**: VoodooHDA 3.7.1, DSDT rename `AZAL` → `HDAS`, `com.apple.driver.AppleHDA` blocked. Tahoe dropped AppleHDA,
  so AppleALC can't work.
- **Brightness / ASUS keys**: SSDT-PNLF + BrightnessKeys 1.0.3, AsusSMC 1.4.1 (Fn keys, fans, keyboard backlight).
- **RestrictEvents**: `revpatch=sbvmm,cpuname revcpu=1`, `revcpuname = "AMD Ryzen 9 6900HX"`.
- **Picker**: OpenCanopy with the Acidanthera GoldenGate theme.

## Wi-Fi and Bluetooth (MT7922)

- The closed angus666888 kexts from the reference EFI (MT7922SkywalkTest, MT7922Bluetooth, KEXTLogKit) are not used.
  Their Bluetooth kext only matches 0489:e0e2 and hung boot when forced onto this laptop's 13d3:3568.
- **Bluetooth**: SimpleMtkBtFw + SimpleMtkBtPatcher 1.1.0, loaded after BlueToolFixup 2.7.2. NVRAM
  `bluetoothInternalControllerInfo` (14 zero bytes) and `bluetoothExternalDongleFailed` (00) make bluetoothd treat the
  card as a third-party dongle. If an iPhone tethered over USB floods the console with "IOMemoryDescriptor ... prepared
  read only" backtraces and boot stalls, disable SimpleMtkBtPatcher.
- **Wi-Fi**: AirportMtkWlan 1.5.0, Tahoe build, MinKernel 25.0.0 / MaxKernel 25.99.99. The build panics on any other
  IO80211 version, so it must never load on Sequoia. `pci-aspm-default = 0` on the Wi-Fi device
  (`PciRoot(0x0)/Pci(0x2,0x1)/Pci(0x0,0x0)`). See [wifi.md](wifi.md).
- **Ethernet**: LucyRTL8125Ethernet; `com.apple.driver.AppleEthernetRL` blocked.

## NVIDIA (NullMoth driver)

Applied by `tools/nvidia-oc-config.sh`, following the driver README and 1401's nullmoth-setup.sh 2.6.4:

- boot-args `nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0`
  plus `nvfbhidpi=1`
- `csr-active-config` = `0x0A43`
- boot-args and csr-active-config in NVRAM > Delete
- SecureBootModel Disabled; AMFIPass after Lilu

`IONDRVSupport` is excluded in **dGPU/MUX mode**, where NVRMFB drives the panel. In **hybrid mode** the panel runs on
the 680M's firmware framebuffer, so IONDRVSupport must stay. Switch with
`tools/nvidia-oc-config.sh --panel hybrid|dgpu`.

The RTX 3060 Laptop is in the driver's device table. Sleep/wake with the driver is not verified on this laptop; the
boot-arg `-nvrmnopm` disables the driver's sleep support.

Kept for debugging: `keepsyms=1 debug=0x100 -lilubetaall -amfipassbeta`. Verbose boot (`-v`) was removed on 2026-11-04;
to see boot text again, add `-v` to boot-args or hold Cmd+V while picking macOS in OpenCore.
