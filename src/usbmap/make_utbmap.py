#!/usr/bin/env python3
"""Write UTBMap.kext (USBToolBox map) for the ROG G513RM, from the Linux USB topology.

XHC0 (06:00.3): HS3 = internal N-KEY keyboard, HS4 = MT7922 Bluetooth (both internal, ACPI says "not used").
XHC1 (06:00.4): two USB-A ports, HS1/HS2 + SS1/SS2 (macOS numbers HS 1-3, then SS 4-5).
XHC3 (07:00.3), XHC4 (07:00.4): one USB-C port each, HS 1 + SS 2.
Usage: make_utbmap.py <out-dir>
"""
import plistlib
import sys
from pathlib import Path

BASE = "IOService:/AppleACPIPlatformExpert/PCI0@0/AppleACPIPCI"
# (name, pci id, path, [(port name, port number, connector, comment)])
CONTROLLERS = [
    ("XHC0", "0x161D1022", "GP17@8,1/IOPP/XHC0@0,3", [
        ("HS03", 3, 255, "Internal keyboard (N-KEY Device)"),
        ("HS04", 4, 255, "Internal Bluetooth (MT7922)"),
    ]),
    ("XHC1", "0x161E1022", "GP17@8,1/IOPP/XHC1@0,4", [
        ("HS01", 1, 3, "USB-A port 1 (USB 2)"),
        ("HS02", 2, 3, "USB-A port 2 (USB 2)"),
        ("SS01", 4, 3, "USB-A port 1 (USB 3)"),
        ("SS02", 5, 3, "USB-A port 2 (USB 3)"),
    ]),
    ("XHC3", "0x15D61022", "GP19@8,3/IOPP/XHC3@0,3", [
        ("HS01", 1, 9, "USB-C port (USB 2)"),
        ("SS01", 2, 9, "USB-C port (USB 3)"),
    ]),
    ("XHC4", "0x15D71022", "GP19@8,3/IOPP/XHC4@0,4", [
        ("HS01", 1, 9, "USB-C port (USB 2)"),
        ("SS01", 2, 9, "USB-C port (USB 3)"),
    ]),
]

le = lambda n: n.to_bytes(4, "little")
personalities = {}
for name, pci, path, ports in CONTROLLERS:
    personalities[name] = {
        "CFBundleIdentifier": "com.dhinakg.USBToolBox.kext",
        "IOClass": "USBToolBox",
        "IOMatchCategory": "USBToolBox",
        "IOPCIPrimaryMatch": pci,
        "IOPathMatch": f"{BASE}/{path}",
        "IOProviderClass": "IOPCIDevice",
        "IOProviderMergeProperties": {
            "port-count": le(max(p[1] for p in ports)),
            "ports": {pn: {"#comment": c, "UsbConnector": conn, "port": le(num)} for pn, num, conn, c in ports},
        },
    }

info = {
    "CFBundleDevelopmentRegion": "English",
    "CFBundleIdentifier": "com.g513rm.UTBMap",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "UTBMap",
    "CFBundlePackageType": "KEXT",
    "CFBundleShortVersionString": "1.0",
    "CFBundleSignature": "????",
    "CFBundleVersion": "1.0",
    "IOKitPersonalities": personalities,
    "OSBundleLibraries": {"com.dhinakg.USBToolBox.kext": "1.0.0"},
    "OSBundleRequired": "Root",
}
out = Path(sys.argv[1]) / "UTBMap.kext/Contents"
out.mkdir(parents=True, exist_ok=True)
with open(out / "Info.plist", "wb") as f:
    plistlib.dump(info, f)
print("wrote", out / "Info.plist", "-", sum(len(c[3]) for c in CONTROLLERS), "ports")
