#!/bin/bash
# OpenCore EFI installer for the ASUS ROG Strix G15 G513RM (Ryzen 9 6900HX, RTX 3060 Laptop, MediaTek MT7922).
# Runs from macOS or Linux. Easiest: double-click Install.command in Finder.
#
#   sudo bash scripts/install.sh              install / update EFI/OC on the internal EFI partition
#   sudo bash scripts/install.sh --dry-run    show what would change, write nothing
#   sudo bash scripts/install.sh --restore    swap back the EFI/OC saved by the last install (run again to undo)
#
# Options: --esp <diskXsY | /dev/nvme0n1p1 | mount point>   use this EFI partition
#          --yes     do not ask for confirmation
#          --force   skip the "is this a G513RM" check
#
# What it does:
#   - finds the EFI partition that already holds OpenCore (or uses --esp), mounting it if needed
#   - keeps your serial numbers: SystemSerialNumber / MLB / SystemUUID / ROM / SystemProductName are copied from the
#     installed config.plist into the new one (the repo only has placeholders); a first install generates new ones
#   - keeps your custom boot picker entries (Misc > Entries, e.g. a named Linux entry) from the installed config.plist
#   - validates the result with ocvalidate before writing anything
#   - saves the current EFI/OC as EFI/OC-backup on the EFI partition (for --restore, works from either OS) and as a
#     dated copy in ~/G513RM-EFI-backups
#   - replaces only EFI/OC. EFI/BOOT is written only if the partition has none, so Pop!_OS / Windows boot entries
#     on a shared EFI partition are left alone
set -euo pipefail

if [ "$(id -u)" != 0 ]; then
    echo "Administrator rights are needed to write the EFI partition."
    exec sudo /bin/bash "$0" "$@"
fi

REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=$REPO/EFI
OS=$(uname -s)
MODE=install; ESP_ARG=""; YES=0; FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) MODE=dry;;
        --restore) MODE=restore;;
        --esp) ESP_ARG=${2:?--esp needs a value}; shift;;
        --yes|-y) YES=1;;
        --force) FORCE=1;;
        -h|--help) sed -n '2,23p' "$0"; exit 0;;
        *) echo "Unknown option: $1"; exit 2;;
    esac
    shift
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
PLACEHOLDER_SERIAL=W00000000001

case "$OS" in
    Darwin) BIN=$REPO/tools/bin; OCV=$BIN/ocvalidate; MACSERIAL=$BIN/macserial
            export COPYFILE_DISABLE=1   # no ._ AppleDouble files on the FAT partition
            CP="cp -RX";;
    Linux)  BIN=$REPO/tools/bin; OCV=$BIN/ocvalidate.linux; MACSERIAL=$BIN/macserial.linux
            CP="cp -R";;
    *) die "unsupported OS $OS (use macOS or Linux)";;
esac
[ -f "$SRC/OC/OpenCore.efi" ] && [ -f "$SRC/OC/config.plist" ] || die "repo EFI not found at $SRC"
if [ "$OS" = Darwin ]; then
    # A repo downloaded as a zip is quarantined; Gatekeeper would then refuse to run ocvalidate/macserial.
    xattr -dr com.apple.quarantine "$REPO" 2>/dev/null || true
fi
chmod +x "$OCV" "$MACSERIAL" 2>/dev/null || true

# ---------------------------------------------------------------- plist helpers (plutil on macOS, python3 on Linux)
pget() {  # pget <plist> <key.path>   -> value (data as base64), empty if missing
    if [ "$OS" = Darwin ]; then
        plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
    else
        python3 -I - "$1" "$2" <<'PY' 2>/dev/null || true
import base64, plistlib, sys
v = plistlib.load(open(sys.argv[1], "rb"))
for k in sys.argv[2].split("."):
    v = v[int(k)] if isinstance(v, list) else v[k]
print(base64.b64encode(v).decode() if isinstance(v, bytes) else v)
PY
    fi
}
pset() {  # pset <plist> <key.path> <string|data> <value; data as base64>
    if [ "$OS" = Darwin ]; then
        plutil -replace "$2" "-$3" "$4" "$1"
    else
        python3 -I - "$@" <<'PY'
import base64, plistlib, sys
p, path, kind, val = sys.argv[1:5]
c = plistlib.load(open(p, "rb"))
d = c
keys = path.split(".")
for k in keys[:-1]:
    d = d[k]
d[keys[-1]] = base64.b64decode(val) if kind == "data" else val
plistlib.dump(c, open(p, "wb"))
PY
    fi
}
pcopy() {  # pcopy <from.plist> <to.plist> <key.path>: copy an array of string/boolean dictionaries; prints its length
    if [ "$OS" = Darwin ]; then
        local n j
        n=$(plutil -extract "$3" raw -o - "$1" 2>/dev/null) || n=0
        case "$n" in ''|*[!0-9]*) n=0;; esac
        if [ "$n" -gt 0 ]; then
            j=$(plutil -extract "$3" json -o - "$1")
            plutil -replace "$3" -json "$j" "$2"
        fi
        echo "$n"
    else
        python3 -I - "$@" <<'PY'
import plistlib, sys
src, dst, path = sys.argv[1:4]
def at(c, keys):
    for k in keys:
        c = c[k]
    return c
keys = path.split(".")
try:
    v = at(plistlib.load(open(src, "rb")), keys)
except (KeyError, TypeError):
    v = []
if isinstance(v, list) and v:
    c = plistlib.load(open(dst, "rb"))
    at(c, keys[:-1])[keys[-1]] = v
    plistlib.dump(c, open(dst, "wb"))
print(len(v) if isinstance(v, list) else 0)
PY
    fi
}

pflat() {  # pflat <plist>: one "key.path = value" line per leaf, for diffs
    # macOS: python3 only if the Command Line Tools are installed (otherwise /usr/bin/python3 pops up an installer)
    if [ "$OS" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then plutil -p "$1"; return; fi
    python3 -I - "$1" <<'PY'
import base64, plistlib, sys
def w(v, p):
    if isinstance(v, dict):
        for k in v: w(v[k], p + "." + k if p else k)
    elif isinstance(v, list):
        for i, x in enumerate(v): w(x, "%s.%d" % (p, i))
    else:
        print("%s = %r" % (p, base64.b64encode(v).decode() if isinstance(v, bytes) else v))
w(plistlib.load(open(sys.argv[1], "rb")), "")
PY
}

# ---------------------------------------------------------------- 1. is this a G513RM?
check_model() {
    local ok=0 what=""
    if [ "$OS" = Linux ]; then
        what=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
        case "$what" in *G513RM*) ok=1;; esac
    else
        # SMBIOS is spoofed under OpenCore, so look at the hardware: Ryzen 6000 CPU + MT7922 Wi-Fi (14c3:7922).
        local cpu; cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
        what="$cpu"
        local pci; pci=$(ioreg -r -c IOPCIDevice -l -w0 2>/dev/null || true)   # not piped into grep -q: pipefail + SIGPIPE
        if [[ "$pci" == *'"device-id" = <22790000>'* && "$pci" == *'"vendor-id" = <c3140000>'* ]]; then
            what="$what + MT7922"
            case "$cpu" in *Ryzen*68*H*|*Ryzen*69*H*) ok=1;; esac
        fi
    fi
    if [ $ok = 1 ]; then say "Hardware: $what (G513RM: OK)"; return; fi
    [ $FORCE = 1 ] && { say "Hardware: '$what' does not look like a G513RM; continuing because of --force"; return; }
    die "this does not look like an ASUS ROG Strix G513RM ('$what'). This EFI is for that model only; use --force to install anyway."
}

# ---------------------------------------------------------------- 2. find the EFI partition
ESP=""; ESP_DEV=""; WE_MOUNTED=""
mount_point_mac() { diskutil info "$1" 2>/dev/null | awk -F': *' '/Mount Point/{print $2}'; }
MP=""
mount_mac() {  # mount_mac <dev>: sets MP to its mount point (mounts it if needed; unmounted again on exit)
    MP=$(mount_point_mac "$1")
    if [ -z "$MP" ]; then
        diskutil mount "$1" >/dev/null 2>&1 || return 1
        MP=$(mount_point_mac "$1"); WE_MOUNTED="$WE_MOUNTED $1"
    fi
    [ -n "$MP" ]
}
cleanup() {
    local d
    sync
    for d in $WE_MOUNTED; do diskutil unmount "$d" >/dev/null 2>&1 || true; done
    if [ -n "${T:-}" ]; then rm -rf "$T"; fi
}
trap cleanup EXIT

find_esp() {
    if [ "$OS" = Darwin ]; then
        if [ -n "$ESP_ARG" ]; then
            if [ -d "$ESP_ARG" ]; then ESP=$ESP_ARG; ESP_DEV=$(df "$ESP" | awk 'NR==2{print $1}' | sed 's#/dev/##')
            else ESP_DEV=${ESP_ARG#/dev/}; mount_mac "$ESP_DEV" || die "cannot mount $ESP_DEV"; ESP=$MP; fi
            return
        fi
        local dev efis=""
        efis=$(diskutil list internal physical 2>/dev/null | awk '$2=="EFI"{print $NF}')
        for dev in $efis; do
            mount_mac "$dev" || continue
            if [ -f "$MP/EFI/OC/OpenCore.efi" ]; then ESP=$MP; ESP_DEV=$dev; break; fi
        done
        if [ -z "$ESP" ]; then
            set -- $efis
            [ $# = 1 ] || die "no EFI partition with OpenCore found and several EFI partitions exist ($efis); pick one with --esp diskXsY"
            ESP_DEV=$1; mount_mac "$1" || die "cannot mount $1"; ESP=$MP
            say "No OpenCore found yet; first install on the only internal EFI partition."
        fi
    else
        if [ -n "$ESP_ARG" ]; then
            if [ -d "$ESP_ARG" ]; then ESP=$ESP_ARG
            else ESP=$(findmnt -no TARGET "$ESP_ARG" 2>/dev/null | head -1)
                 [ -n "$ESP" ] || { ESP=/mnt/g513rm-esp; mkdir -p "$ESP"; mount "$ESP_ARG" "$ESP"; }; fi
        else
            for ESP in /boot/efi /efi /boot; do [ -d "$ESP/EFI" ] && break; done
            [ -d "$ESP/EFI" ] || die "EFI partition not mounted (tried /boot/efi, /efi, /boot); use --esp /dev/nvme0n1p1"
        fi
        ESP_DEV=$(findmnt -no SOURCE "$ESP" 2>/dev/null || true)
        [ "$(findmnt -no FSTYPE "$ESP" 2>/dev/null)" = vfat ] || die "$ESP is not a FAT (EFI) partition"
    fi
}

# ---------------------------------------------------------------- summary of what changes
summary() {  # summary <old OC dir> <new OC dir>
    local old=$1 new=$2 k
    say "Kexts:"
    for k in $( (ls "$old/Kexts" 2>/dev/null; ls "$new/Kexts") | grep '\.kext$' | sort -u); do
        if [ ! -d "$old/Kexts/$k" ]; then say "  + $k (new)"
        elif [ ! -d "$new/Kexts/$k" ]; then say "  - $k (removed)"
        elif ! diff -rq "$old/Kexts/$k" "$new/Kexts/$k" >/dev/null 2>&1; then
            say "  ~ $k ($(pget "$old/Kexts/$k/Contents/Info.plist" CFBundleVersion) -> $(pget "$new/Kexts/$k/Contents/Info.plist" CFBundleVersion), files differ)"
        fi
    done
    local G=7C436110-AB2A-4BBB-A880-FE41995C9F82
    local ob nb; ob=$(pget "$old/config.plist" "NVRAM.Add.$G.boot-args"); nb=$(pget "$new/config.plist" "NVRAM.Add.$G.boot-args")
    [ "$ob" = "$nb" ] && say "boot-args: unchanged" || { say "boot-args (installed): $ob"; say "boot-args (new):       $nb"; }
    if cmp -s "$old/config.plist" "$new/config.plist"; then say "config.plist: identical"
    else
        say "config.plist changes (< installed, > new):"
        diff <(pflat "$old/config.plist") <(pflat "$new/config.plist") | grep '^[<>]' | head -40 | sed 's/^/  /' || true
    fi
    cmp -s "$old/OpenCore.efi" "$new/OpenCore.efi" && say "OpenCore.efi: same" || say "OpenCore.efi: different build"
}

# ---------------------------------------------------------------- restore
do_restore() {
    local E=$ESP/EFI
    [ -d "$E/OC-backup" ] || die "no $E/OC-backup to restore"
    say "Swapping $E/OC and $E/OC-backup (run --restore again to swap back)."
    if [ $YES = 0 ]; then read -r -p "Continue? [y/N] " a; case "$a" in y|Y|yes) ;; *) die "cancelled";; esac; fi
    rm -rf "$E/OC.swap"
    mv "$E/OC" "$E/OC.swap"; mv "$E/OC-backup" "$E/OC"; mv "$E/OC.swap" "$E/OC-backup"; sync
    say "RESTORED. Reboot to use it."
}

# ================================================================ main
say "ASUS ROG Strix G513RM OpenCore EFI installer  (repo: $REPO)"
check_model
find_esp
say "EFI partition: ${ESP_DEV:-?} mounted at $ESP"
[ "$MODE" = restore ] && { do_restore; exit 0; }

step "Preparing the new EFI/OC"
T=$(mktemp -d); NEW=$T/OC
$CP "$SRC/OC" "$NEW"
find "$NEW" -name '.DS_Store' -delete
CUR=$ESP/EFI/OC/config.plist
SER=""; MLB=""; UUID=""; ROM=""; MODEL=""
if [ -f "$CUR" ]; then
    SER=$(pget "$CUR" PlatformInfo.Generic.SystemSerialNumber); MLB=$(pget "$CUR" PlatformInfo.Generic.MLB)
    UUID=$(pget "$CUR" PlatformInfo.Generic.SystemUUID);       ROM=$(pget "$CUR" PlatformInfo.Generic.ROM)
    MODEL=$(pget "$CUR" PlatformInfo.Generic.SystemProductName)
fi
if [ -n "$SER" ] && [ "$SER" != "$PLACEHOLDER_SERIAL" ] && [ -n "$MLB" ] && [ -n "$UUID" ] && [ -n "$ROM" ]; then
    say "Keeping the serial numbers of the installed config ($MODEL, serial ${SER:0:3}*********)."
else
    MODEL=$(pget "$NEW/config.plist" PlatformInfo.Generic.SystemProductName)
    say "No serial numbers installed yet: generating new ones for $MODEL with macserial."
    line=$("$MACSERIAL" -m "$MODEL" -g -n 1) || die "macserial failed"
    SER=$(printf '%s' "$line" | awk -F' [|] ' '{print $1}'); MLB=$(printf '%s' "$line" | awk -F' [|] ' '{print $2}')
    UUID=$( (uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid) | tr 'a-z' 'A-Z')
    ROM=$(head -c 6 /dev/urandom | base64)
    [ ${#SER} -ge 12 ] && [ ${#MLB} -ge 13 ] || die "unexpected macserial output: $line"
    say "Note: these identify this Mac to Apple (iCloud, iMessage). Keep the installed config.plist; reinstalling keeps them."
fi
NC=$NEW/config.plist
pset "$NC" PlatformInfo.Generic.SystemSerialNumber string "$SER"
pset "$NC" PlatformInfo.Generic.MLB string "$MLB"
pset "$NC" PlatformInfo.Generic.SystemUUID string "$UUID"
pset "$NC" PlatformInfo.Generic.ROM data "$ROM"
pset "$NC" PlatformInfo.Generic.SystemProductName string "$MODEL"
if [ -f "$CUR" ]; then
    NENT=$(pcopy "$CUR" "$NC" Misc.Entries)
    if [ "$NENT" -gt 0 ]; then say "Keeping the $NENT custom boot picker entr$([ "$NENT" = 1 ] && echo y || echo ies) of the installed config (Misc > Entries)."; fi
fi
[ "$OS" = Darwin ] && plutil -convert xml1 "$NC"

step "Validating config.plist with ocvalidate"
out=$("$OCV" "$NC" 2>&1 | tail -1); say "$out"
case "$out" in *"No issues found"*) ;; *) die "the new config.plist does not validate; nothing was written";; esac

step "Changes"
if [ -d "$ESP/EFI/OC" ]; then summary "$ESP/EFI/OC" "$NEW"; else say "First install: everything is new."; fi
NEED_BOOT=0; [ -e "$ESP/EFI/BOOT/BOOTx64.efi" ] || NEED_BOOT=1
[ $NEED_BOOT = 1 ] && say "EFI/BOOT/BOOTx64.efi is missing on the partition: it will be added (fallback boot entry)."
[ "$MODE" = dry ] && { say; say "DRY RUN: nothing written."; exit 0; }

if [ $YES = 0 ]; then
    echo; read -r -p "Install this EFI on $ESP? [y/N] " a
    case "$a" in y|Y|yes) ;; *) die "cancelled, nothing written";; esac
fi

step "Backing up the current EFI/OC"
TS=$(date +%Y%m%d-%H%M%S)
if [ -d "$ESP/EFI/OC" ]; then
    U=${SUDO_USER:-root}; H=$(eval echo "~$U")
    BK=$H/G513RM-EFI-backups/OC-$TS
    mkdir -p "$BK"; $CP "$ESP/EFI/OC/." "$BK/"; chown -R "$U" "$H/G513RM-EFI-backups" 2>/dev/null || true
    say "Saved to $BK"
fi

step "Writing EFI/OC"
mkdir -p "$ESP/EFI"
rm -rf "$ESP/EFI/OC.new"
$CP "$NEW" "$ESP/EFI/OC.new"; sync
diff -rq "$NEW" "$ESP/EFI/OC.new" >/dev/null || die "copy verification failed; the installed EFI/OC was not touched ($ESP/EFI/OC.new is the partial copy)"
if [ -d "$ESP/EFI/OC" ]; then
    rm -rf "$ESP/EFI/OC-backup"; mv "$ESP/EFI/OC" "$ESP/EFI/OC-backup"
    mv "$ESP/EFI/OC.new" "$ESP/EFI/OC"; sync
    say "Installed. Previous EFI/OC kept as $ESP/EFI/OC-backup."
else
    mv "$ESP/EFI/OC.new" "$ESP/EFI/OC"; sync
    say "Installed."
fi
if [ $NEED_BOOT = 1 ]; then
    mkdir -p "$ESP/EFI/BOOT"; $CP "$SRC/BOOT/." "$ESP/EFI/BOOT/"; sync; say "Added EFI/BOOT/BOOTx64.efi."
fi

# A firmware boot entry for OpenCore (Linux only: efibootmgr). Keeps the current boot order first.
if [ "$OS" = Linux ] && command -v efibootmgr >/dev/null &&
   ! [[ "$(efibootmgr -v 2>/dev/null | tr 'a-z' 'A-Z')" == *'\EFI\OC\OPENCORE.EFI'* ]]; then
    disk=/dev/$(lsblk -no PKNAME "$ESP_DEV"); part=$(cat "/sys/class/block/$(basename "$ESP_DEV")/partition")
    order=$(efibootmgr | sed -n 's/^BootOrder: //p'); before=$(efibootmgr | grep -o '^Boot[0-9A-F]\{4\}' | sort)
    efibootmgr -q -c -d "$disk" -p "$part" -L OpenCore -l '\EFI\OC\OpenCore.efi'
    newe=$(comm -13 <(echo "$before") <(efibootmgr | grep -o '^Boot[0-9A-F]\{4\}' | sort) | sed 's/^Boot//' | head -1)
    [ -n "$newe" ] && [ -n "$order" ] && efibootmgr -q -o "$order,$newe"
    say "Added firmware boot entry \"OpenCore\" (after the existing ones; pick it with F8 at power-on or move it up in the BIOS)."
fi

echo
say "DONE. Reboot to load the new EFI. If it does not boot: start the other OS (or pick 'OpenCore' from F8 and"
say "boot your backup) and run:  sudo bash scripts/install.sh --restore"
