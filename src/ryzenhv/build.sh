#!/bin/bash
# Rebuild RyzenHV.kext (AMD SVM back end for Hypervisor.framework, for Docker Desktop) from source and put it into this
# repo's EFI/OC/Kexts. Needs macOS with the Command Line Tools and network access (clones the upstream project).
#
#   bash src/ryzenhv/build.sh            build, then replace EFI/OC/Kexts/RyzenHV.kext
#   bash src/ryzenhv/build.sh --no-copy  build only (result in build/ryzenhv/build/)
#
# Upstream: OverlordDev/ryzen-hypervisor.framework v0.7.9-beta (commit 99627c6, MIT), plus g513rm-fixes.patch
# (see docs/ryzenhv-review.md):
#   1. VmProtect never makes a page writable that was pinned read-only (guest writes into read-only files)
#   2. HvControl changes (native mode, kern.hv_support, SVM limits, debugging) and the log level need real root,
#      even with rhv_allow_users=1; reading the log needs the VM privilege
#   3. the shim unsets DYLD_INSERT_LIBRARIES in every process except Docker's backend (whose "services" process runs the
#      hypervisor check), so it does not spread through everything Docker starts; the HyperKit wrapper sets it only for
#      HyperKit; /tmp/rhv-debug (world-writable) no longer switches on guest-memory tracing
#   4. XSETBV is always intercepted and the host XCR0 is always restored after VMRUN (a guest could panic the host)
#   5. the Docker installer also sets EngineTypeMac=hyperkit, the setting Docker 4.99 uses instead of
#      UseVirtualizationFramework
#   6. host file sharing: Docker 4.99 no longer listens on HyperKit's socket for guest port 4099, so a container with a
#      host bind mount hung at start. scripts/docker-fs-bridge.py (new) hands those connections to Docker's file
#      server; the installer copies it to ~/.ryzenhv and the HyperKit wrapper starts it with every VM
# The shim (build/ryzenhv/build/libryzenhv.dylib) and rhv-info stay in build/; see docs/ryzenhv.md for Docker.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
COMMIT=99627c611
WORK=$REPO/build/ryzenhv
COPY=1; [ "${1:-}" = --no-copy ] && COPY=0
xcrun -f ld >/dev/null 2>&1 || { echo "ABORT: Command Line Tools missing; run: xcode-select --install"; exit 1; }

rm -rf "$WORK"; mkdir -p "$(dirname "$WORK")"
git clone -q https://github.com/OverlordDev/ryzen-hypervisor.framework.git "$WORK"
cd "$WORK"
git checkout -q "$COMMIT"
git apply "$HERE/g513rm-fixes.patch"
git diff --stat | tail -1

make test >/dev/null || { echo "ABORT: unit tests failed (run make test in $WORK)"; exit 1; }
echo "unit tests: OK"
make kext shim tools >"$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; echo "ABORT: build failed ($WORK/build.log)"; exit 1; }
grep 'check-kext-symbols:' "$WORK/build.log" || true     # "all N imported symbols resolve against this kernel"
K=$WORK/build/RyzenHV.kext
[ -f "$K/Contents/MacOS/RyzenHV" ] || { echo "ABORT: build produced no kext"; exit 1; }
shasum -a 256 "$K/Contents/MacOS/RyzenHV" "$WORK/build/libryzenhv.dylib"
if [ $COPY = 1 ]; then
    rm -rf "$REPO/EFI/OC/Kexts/RyzenHV.kext"
    cp -RX "$K" "$REPO/EFI/OC/Kexts/"
    echo "BUILT-OK: copied to EFI/OC/Kexts/RyzenHV.kext. Test on a USB EFI first (docs/ryzenhv.md)."
else
    echo "BUILT-OK: $K"
fi
