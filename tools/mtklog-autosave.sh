#!/bin/sh
# Save the MT7922 Wi-Fi driver's own log (MtkDebugLog, see tools/mtklog.sh) once per boot, at login.
# That log lives only in the IORegistry and is gone after the next boot, so a boot where Wi-Fi failed to start
# could not be diagnosed once the laptop had been power-cycled to fix it.
#
#   sh tools/mtklog-autosave.sh --install     install a LaunchAgent for this user (no sudo)
#   sh tools/mtklog-autosave.sh --uninstall   remove it (saved logs are kept)
#   sh tools/mtklog-autosave.sh --run         save now (what the LaunchAgent runs)
#
# Logs: ~/Library/Logs/AirportMtkWlan/boot-<boot time>.log, newest 30 kept. If the Wi-Fi controller did not start,
# the file name ends in -FAILED and a notification is shown.
set -eu
LABEL=com.g513rm.mtklog-autosave
AGENT=$HOME/Library/LaunchAgents/$LABEL.plist
SCRIPT=$HOME/Library/Application\ Support/G513RM/mtklog-autosave.sh
LOGDIR=$HOME/Library/Logs/AirportMtkWlan

save() {
    mkdir -p "$LOGDIR"
    sec=$(sysctl -n kern.boottime | sed -E 's/^[{] sec = ([0-9]+),.*/\1/')
    stamp=$(date -r "$sec" +%Y%m%d-%H%M%S)
    ls "$LOGDIR"/boot-"$stamp"*.log >/dev/null 2>&1 && return 0     # this boot is already saved
    n=$(ioclasscount AirportItlwm 2>/dev/null | sed -E 's/.*= *//')
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    out=$LOGDIR/boot-$stamp.log
    [ "$n" -eq 0 ] && out=$LOGDIR/boot-$stamp-FAILED.log
    {
        echo "boot: $(date -r "$sec")  saved: $(date)  AirportItlwm instances: $n"
        echo "loaded: $(kmutil showloaded 2>/dev/null | grep -oE 'com.flxxxxddd.AirportMtkWlan.*' || echo none)"
        ioreg -l -w0 -r -c IOPCIDevice | awk '/"MtkDebugLog" = "/{f=1} f{ if (n++ && /^ *"[A-Za-z-]+" = /) exit; print }'
    } > "$out"
    ls -t "$LOGDIR"/boot-*.log 2>/dev/null | tail -n +31 | while read -r f; do rm -f "$f"; done
    if [ "$n" -eq 0 ]; then
        osascript -e "display notification \"The Wi-Fi driver failed to start. Its log was saved to $out\" with title \"Wi-Fi\"" \
            >/dev/null 2>&1 || true
    fi
}

case "${1:-}" in
--run)
    sleep 20        # let the driver finish starting
    save ;;
--install)
    mkdir -p "$(dirname "$SCRIPT")" "$(dirname "$AGENT")"
    cp "$0" "$SCRIPT"; chmod 755 "$SCRIPT"
    cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/sh</string><string>$SCRIPT</string><string>--run</string></array>
    <key>RunAtLoad</key><true/>
    <key>LowPriorityIO</key><true/>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$AGENT"
    echo "installed: $AGENT (runs at login; logs in $LOGDIR)" ;;
--uninstall)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$AGENT" "$SCRIPT"
    echo "removed (logs kept in $LOGDIR)" ;;
*)
    sed -n '2,13p' "$0"; exit 2 ;;
esac
