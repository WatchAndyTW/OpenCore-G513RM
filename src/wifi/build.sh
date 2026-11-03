#!/bin/bash
# Rebuild AirportMtkWlan.kext (MT7922 Wi-Fi) from source and put it into this repo's EFI/OC/Kexts.
# Needs macOS with the Command Line Tools (xcode-select --install) and network access (clones the upstream driver).
#
#   bash src/wifi/build.sh            build, then replace EFI/OC/Kexts/AirportMtkWlan.kext
#   bash src/wifi/build.sh --no-copy  build only (result in build/SimpleMtkWlan/build/Debug/tahoe/)
#
# Upstream: flxxxxddd/SimpleMtkWlan v1.5.0 (commit 9a9c2ea, GPL-2.0), Debug build for macOS Tahoe (26), plus
#   - mtk-fixes.patch: 802.1X / WPA2-Enterprise fixes, TX rate + DMA fixes (upstream PRs 1 and 2), shorter background
#     scans, and the warm-reboot fixes (see docs/wifi.md)
#   - firmware/*.bin: MT7922 firmware from linux-firmware 20260724, embedded with gen_fwbinary.py
# Then run scripts/install.sh to install the updated EFI.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
COMMIT=9a9c2ea
WORK=$REPO/build/SimpleMtkWlan
COPY=1; [ "${1:-}" = --no-copy ] && COPY=0
xcrun -f ld >/dev/null 2>&1 || { echo "ABORT: Command Line Tools missing; run: xcode-select --install"; exit 1; }

FW=$HERE/firmware
( cd "$FW" && shasum -a 256 -c - ) <<'SUMS'
7fc9075d6d54b31e0539734614ca971fa52caf41b642a3000c8a4501591a4d98  WIFI_MT7922_patch_mcu_1_1_hdr.bin
d100e5e04c324fc8da6302112d1e0b4fac952286447d2419eabcd8fb0a1f5b93  WIFI_RAM_CODE_MT7922_1.bin
SUMS

rm -rf "$WORK"; mkdir -p "$(dirname "$WORK")"
git clone -q https://github.com/flxxxxddd/SimpleMtkWlan.git "$WORK"
cd "$WORK"
git checkout -q "$COMMIT"
git submodule -q update --init --depth 1 MacKernelSDK
git apply "$HERE/mtk-fixes.patch"
python3 -I "$FW/gen_fwbinary.py" include/FwBinary.cpp include/FwBinary.cpp \
    "$FW/WIFI_MT7922_patch_mcu_1_1_hdr.bin" "$FW/WIFI_RAM_CODE_MT7922_1.bin"
git diff --stat | tail -1

./build-macos.sh Debug AirportMtkWlan
K=$WORK/build/Debug/tahoe/AirportMtkWlan.kext
[ -f "$K/Contents/MacOS/AirportMtkWlan" ] || { echo "ABORT: build produced no kext"; exit 1; }
echo "## unresolved kernel symbols (should be none):"
kmutil libraries -p "$K" --undef-symbols 2>&1 | grep -iA20 unresolved || echo "none"
shasum -a 256 "$K/Contents/MacOS/AirportMtkWlan"
if [ $COPY = 1 ]; then
    rm -rf "$REPO/EFI/OC/Kexts/AirportMtkWlan.kext"
    cp -RX "$K" "$REPO/EFI/OC/Kexts/"
    echo "BUILT-OK: copied to EFI/OC/Kexts/AirportMtkWlan.kext. Install with: sudo bash scripts/install.sh"
else
    echo "BUILT-OK: $K"
fi
