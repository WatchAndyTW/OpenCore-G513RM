#!/bin/bash
#
# Switches RyzenHV native mode on at every boot (Kiri's Virtualization.framework VM needs it; Docker Desktop's
# shim mode does not). A root LaunchDaemon runs a root-owned copy of rhv-info, never the one in this repo, so no
# program running as you can change what root runs (unlike `rhv autostart`, see docs/ryzenhv-review.md finding 4).
#
#   sudo scripts/ryzenhv-native-boot.sh install     copy rhv-info, install and start the daemon
#   sudo scripts/ryzenhv-native-boot.sh uninstall   remove both; native mode stays on until the next reboot
#        scripts/ryzenhv-native-boot.sh status
#
# Re-run install after rebuilding the kext tools. Log: /var/log/ryzenhv-native.log
set -eu

LABEL=local.ryzenhv.native
PLIST=/Library/LaunchDaemons/$LABEL.plist
DIR=/Library/PrivilegedHelperTools/ryzenhv
BIN=$DIR/rhv-info
LOG=/var/log/ryzenhv-native.log
SRC="$(cd "$(dirname "$0")/.." && pwd)/build/ryzenhv/build/rhv-info"

need_root() { [ "$(id -u)" = 0 ] || { echo "run it with sudo" >&2; exit 1; }; }

case "${1:-status}" in
install)
    need_root
    [ -x "$SRC" ] || { echo "missing $SRC: build RyzenHV first (src/ryzenhv/build.sh)" >&2; exit 1; }
    install -d -o root -g wheel -m 755 "$(dirname "$DIR")" "$DIR"
    install -o root -g wheel -m 755 "$SRC" "$BIN"
    # The kext may not have matched yet when launchd starts us: retry for up to 3 minutes.
    # Both commands are idempotent (a second "mode 1" or "sysctl 1" just answers success).
    cat > "$PLIST.tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>i=0; while [ \$i -lt 90 ]; do if $BIN hv mode 1 &amp;&amp; $BIN hv sysctl 1; then echo "\$(date): native mode on"; exit 0; fi; i=\$((i+1)); /bin/sleep 2; done; echo "\$(date): gave up, RyzenHV did not answer"; exit 1</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF
    plutil -lint "$PLIST.tmp" >/dev/null
    chown root:wheel "$PLIST.tmp"
    chmod 644 "$PLIST.tmp"
    mv "$PLIST.tmp" "$PLIST"
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    launchctl bootstrap system "$PLIST"
    /bin/sleep 3
    tail -n 3 "$LOG"
    ;;
uninstall)
    need_root
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$DIR"
    echo "removed; native mode stays on until the next reboot"
    ;;
status)
    if [ -f "$PLIST" ]; then echo "daemon: installed ($PLIST)"; else echo "daemon: not installed"; fi
    [ -f "$LOG" ] && tail -n 3 "$LOG"
    "$SRC" hv
    ;;
*)
    echo "usage: $0 install | uninstall | status" >&2
    exit 2
    ;;
esac
