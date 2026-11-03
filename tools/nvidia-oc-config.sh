#!/bin/bash
# Set up the OpenCore config on the internal EFI partition for the NullMoth NVIDIA driver (nullmoth/nvidia-macos-driver),
# from Pop!_OS, instead of letting the 1401 Mac app edit it. The 1401 app on this G513RM would:
#   - replace the USB map with one that drops the internal keyboard (N-KEY Device, XHC0 port 3), and
#   - exclude IONDRVSupport, because its built-in-screen check only knows Intel iGPUs; in hybrid mode the panel is on
#     the 680M's firmware framebuffer, so that would leave it dark.
#
# Usage (Pop!_OS):
#   sudo bash nvidia-oc-config.sh [--dry]            apply the driver settings (panel mode from the current MUX setting)
#   sudo bash nvidia-oc-config.sh --panel hybrid     force: built-in screen on the 680M (IONDRVSupport stays on)
#   sudo bash nvidia-oc-config.sh --panel dgpu       force: built-in screen on the RTX 3060 (MUX on; exclude IONDRVSupport)
#   sudo bash nvidia-oc-config.sh --off              park the driver for the next boots (-nvoff), keep everything else
#   sudo bash nvidia-oc-config.sh --on               undo --off
#   sudo bash nvidia-oc-config.sh --revert           put back the config from before the first run of this script
#
# Settings follow the driver README ("Wiring into an existing OpenCore setup") and 1401's nullmoth-setup.sh 2.6.4:
# boot-args WANT_ARGS, csr-active-config |= 0x0A43, SecureBootModel Disabled, Lilu + AMFIPass on (AMFIPass after Lilu),
# boot-args/csr-active-config in NVRAM Delete, BAR settings preserved, DisableVariableWrite on for AMD configs that remap
# memory (DevirtualiseMmio), Algrey's Fix PAT (already the case here). The USB map is never touched.
set -euo pipefail

ESP=/boot/efi
C=$ESP/EFI/OC/config.plist
OCV=$(cd "$(dirname "$0")" && pwd)/bin/ocvalidate.linux
MUX=/sys/devices/platform/asus-nb-wmi/gpu_mux_mode
FIRST_BACKUP=$ESP/EFI/OC/config.plist.pre-nvidia

MODE=apply; PANEL=auto; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry) DRY=1;;
        --panel) PANEL=${2:-}; shift;;
        --off) MODE=off;; --on) MODE=on;; --revert) MODE=revert;;
        *) echo "unknown option: $1"; exit 2;;
    esac
    shift
done
case "$PANEL" in auto|hybrid|dgpu) ;; *) echo "--panel takes hybrid or dgpu"; exit 2;; esac

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
findmnt "$ESP" >/dev/null || { echo "ABORT: $ESP is not mounted"; exit 1; }
[ -f "$C" ] || { echo "ABORT: no OpenCore config at $C"; exit 1; }
[ -x "$OCV" ] || { echo "ABORT: ocvalidate not found at $OCV"; exit 1; }

if [ "$MODE" = revert ]; then
    [ -f "$FIRST_BACKUP" ] || { echo "ABORT: no $FIRST_BACKUP (this script never changed the config)"; exit 1; }
    cp -p "$C" "$C.before-revert-$(date +%Y%m%d-%H%M%S)"
    cp -p "$FIRST_BACKUP" "$C.new" && sync && mv "$C.new" "$C" && sync
    echo "Restored $C from $FIRST_BACKUP. The driver files stay in macOS; run its uninstall.sh there to remove them."
    exit 0
fi

if [ "$PANEL" = auto ]; then
    case "$(cat "$MUX" 2>/dev/null || echo x)" in
        1) PANEL=hybrid;; 0) PANEL=dgpu;;
        *) echo "ABORT: cannot read $MUX; pass --panel hybrid or --panel dgpu"; exit 1;;
    esac
    echo "MUX setting now: $PANEL (gpu_mux_mode=$(cat "$MUX")). The config is for booting in this mode."
fi

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -p "$C" "$T/config.plist"

python3 -I - "$T/config.plist" "$MODE" "$PANEL" "$(grep -m1 -o 'AMD' /proc/cpuinfo || true)" <<'PY' || { echo "ABORT: see PROBLEM lines above; nothing written"; exit 1; }
import plistlib, sys

path, mode, panel, amd = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "AMD"
G = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
WANT = "nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0".split()
DROP = {"nv_disable=1", "-wegnoegpu", "agdpmod=pikera"}
SIP_BITS = 0x0A43

with open(path, "rb") as f:
    c = plistlib.load(f)
changes, problems = [], []
add = c["NVRAM"]["Add"].setdefault(G, {})
args = add.get("boot-args", "").split()

if mode in ("off", "on"):
    has = "-nvoff" in args
    if mode == "off" and not has:
        args.append("-nvoff"); changes.append("boot-args: add -nvoff (driver parked)")
    if mode == "on" and has:
        args = [a for a in args if a != "-nvoff"]; changes.append("boot-args: remove -nvoff")
    add["boot-args"] = " ".join(args)
else:
    for a in [a for a in args if a in DROP]:
        args.remove(a); changes.append(f"boot-args: remove {a} (hides the NVIDIA card)")
    for a in WANT:
        if a not in args:
            args.append(a); changes.append(f"boot-args: add {a}")
    add["boot-args"] = " ".join(args)

    cur = int.from_bytes(add.get("csr-active-config", b"\0\0\0\0")[:4].ljust(4, b"\0"), "little")
    want = cur | SIP_BITS
    if want != cur:
        add["csr-active-config"] = want.to_bytes(4, "little")
        changes.append(f"csr-active-config: 0x{cur:04X} -> 0x{want:04X}")

    dele = c["NVRAM"].setdefault("Delete", {}).setdefault(G, [])
    for k in ("boot-args", "csr-active-config", "nullmoth-remove"):
        if k not in dele:
            dele.append(k); changes.append(f"NVRAM Delete: add {k}")

    sec = c["Misc"]["Security"]
    if sec.get("SecureBootModel") != "Disabled":
        changes.append(f"SecureBootModel: {sec.get('SecureBootModel')} -> Disabled"); sec["SecureBootModel"] = "Disabled"

    kadd = c["Kernel"]["Add"]
    pos = {e["BundlePath"]: i for i, e in enumerate(kadd)}
    for k in ("Lilu.kext", "AMFIPass.kext"):
        if k not in pos:
            problems.append(f"{k} is not in Kernel > Add")
        elif not kadd[pos[k]]["Enabled"]:
            kadd[pos[k]]["Enabled"] = True; changes.append(f"Kernel > Add: turn {k} on")
    if "Lilu.kext" in pos and "AMFIPass.kext" in pos and pos["AMFIPass.kext"] < pos["Lilu.kext"]:
        problems.append("AMFIPass.kext loads before Lilu.kext")

    # Firmware framebuffer: needed for the panel in hybrid mode, must go when NVRMFB drives the panel (MUX/dGPU mode).
    block = c["Kernel"].setdefault("Block", [])
    ion = [b for b in block if b.get("Identifier") == "com.apple.iokit.IONDRVSupport"]
    if panel == "dgpu":
        if not ion:
            block.append({"Arch": "Any", "Comment": "NullMoth: NVRMFB owns the display (MUX/dGPU mode)", "Enabled": True,
                          "Identifier": "com.apple.iokit.IONDRVSupport", "MaxKernel": "", "MinKernel": "",
                          "Strategy": "Exclude"})
            changes.append("Kernel > Block: exclude IONDRVSupport (dGPU mode)")
        elif not ion[0]["Enabled"]:
            ion[0]["Enabled"] = True; changes.append("Kernel > Block: IONDRVSupport exclude on (dGPU mode)")
    else:
        for b in ion:
            if b["Enabled"]:
                b["Enabled"] = False; changes.append("Kernel > Block: IONDRVSupport exclude off (hybrid: panel is on the 680M)")

    q = c["Booter"]["Quirks"]
    if amd and (q.get("DevirtualiseMmio") or q.get("SetupVirtualMap")) and not q.get("DisableVariableWrite"):
        drivers = [d["Path"] for d in c["UEFI"]["Drivers"] if d.get("Enabled", True)]
        if "OpenRuntime.efi" in drivers:
            q["DisableVariableWrite"] = True
            changes.append("Booter > Quirks: DisableVariableWrite on (AMD + DevirtualiseMmio; 1401 policy)")
        else:
            problems.append("DisableVariableWrite wanted but OpenRuntime.efi is not loaded")

    for p in c["Kernel"]["Patch"]:
        if "Fix PAT" in p["Comment"] and "haneee" in p["Comment"] and p["Enabled"]:
            problems.append(f"Shaneee's Fix PAT is on ({p['Comment']}); the driver needs Algrey's")

# Report things this script leaves alone.
kadd = c["Kernel"]["Add"]
usb = {e["BundlePath"]: e["Enabled"] for e in kadd if e["BundlePath"] in ("UTBDefault.kext", "UTBMap.kext", "USBToolBox.kext")}
print("USB map (unchanged):", usb)
print("BAR (unchanged): ResizeGpuBars", c["UEFI"]["Quirks"].get("ResizeGpuBars"),
      "ResizeAppleGpuBars", c["Booter"]["Quirks"].get("ResizeAppleGpuBars"))
print("SMBIOS (unchanged):", c["PlatformInfo"]["Generic"]["SystemProductName"])
for p in problems:
    print("PROBLEM:", p)
for ch in changes:
    print("CHANGE", ch)
if not changes:
    print("Nothing to change.")
print("boot-args now:", c["NVRAM"]["Add"][G]["boot-args"])
with open(path, "wb") as f:
    plistlib.dump(c, f)
sys.exit(3 if problems else 0)
PY

out=$("$OCV" "$T/config.plist" 2>&1 | tail -1)
echo "$out"
case "$out" in *"No issues found"*) ;; *) echo "ABORT: the edited config does not validate; nothing written"; exit 1;; esac

if cmp -s "$C" "$T/config.plist"; then echo "Config already up to date."; exit 0; fi
if [ $DRY = 1 ]; then echo "(--dry: nothing written)"; exit 0; fi

[ -f "$FIRST_BACKUP" ] || cp -p "$C" "$FIRST_BACKUP"
cp -p "$C" "$C.bak-$(date +%Y%m%d-%H%M%S)"
cp "$T/config.plist" "$C.new" && sync && mv "$C.new" "$C" && sync
cmp -s "$C" "$T/config.plist" && echo "Written: $C (first backup: $FIRST_BACKUP)"
