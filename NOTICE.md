# Third-party components

This repository redistributes unmodified third-party binaries, plus one modified driver, under their own licences:

| Component | Where | Licence |
|---|---|---|
| OpenCore 1.0.8 (OpenCore.efi, BOOTx64.efi, drivers, OpenShell resources, ocvalidate, macserial) | `EFI/`, `tools/bin/` | BSD-3-Clause, acidanthera |
| OcBinaryData (OpenCanopy theme, fonts, labels) | `EFI/OC/Resources/` | acidanthera, see OcBinaryData |
| Lilu, VirtualSMC, SMCBatteryManager, RestrictEvents, NVMeFix, BlueToolFixup, BrightnessKeys, VoodooPS2Controller | `EFI/OC/Kexts/` | BSD-3-Clause, acidanthera |
| AMDRyzenCPUPowerManagement, SMCAMDProcessor | `EFI/OC/Kexts/` | trulyspinach, see upstream |
| VoodooI2C, VoodooI2CHID | `EFI/OC/Kexts/` | GPL-2.0 |
| AsusSMC | `EFI/OC/Kexts/` | GPL-3.0, hieplpvip |
| ECEnabler | `EFI/OC/Kexts/` | 1Revenger1, see upstream |
| USBToolBox, AMFIPass | `EFI/OC/Kexts/` | dhinakg, see upstream |
| LucyRTL8125Ethernet | `EFI/OC/Kexts/` | Laura Müller (Mieze), see upstream |
| VoodooHDA | `EFI/OC/Kexts/` | see upstream |
| XHCILagFix, USBXHCIWakeup, AppleMCEReporterDisabler | `EFI/OC/Kexts/` | from the reference G513RM EFI (Xelon233/ROG-G15-Series-OpenCore) |
| SimpleMtkBtFw, SimpleMtkBtPatcher 1.1.0 | `EFI/OC/Kexts/` | GPL-3.0, flxxxxddd |
| AirportMtkWlan (SimpleMtkWlan 1.5.0, **modified**) | `EFI/OC/Kexts/` | GPL-2.0, flxxxxddd. Corresponding source: upstream commit `9a9c2ea` + `src/wifi/mtk-fixes.patch` + `src/wifi/firmware/` (`src/wifi/build.sh` rebuilds it) |
| MediaTek MT7922 firmware (WIFI_MT7922_patch_mcu_1_1_hdr.bin, WIFI_RAM_CODE_MT7922_1.bin) | `src/wifi/firmware/`, embedded in AirportMtkWlan | MediaTek redistribution licence, as shipped in linux-firmware (`LICENCE.mediatek`, `WHENCE`), build 20260724 |
| NullMothSafe.efi | `EFI/OC/Tools/` | NullMoth / 1401 project |

The scripts and documentation written for this repository (`Install.command`, `scripts/`, `tools/*.sh`, `src/acpi/`,
`src/usbmap/`, `src/wifi/build.sh`, `docs/`) may be used freely.
