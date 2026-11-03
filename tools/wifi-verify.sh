#!/bin/zsh
# Read-only check of the 802.1X / IPv4 fixes after joining Wi-Fi (no sudo needed):
#   zsh wifi-verify.sh [minutes]   (default 15)   add --speed to also run networkQuality on en4
# Each join should show, in order:  join 8021X -> supplicant done (driver) -> IO80211RSNDone set=<1>
#   -> ipv4 valid = <1>  ... and NO "4wayHsTimeout", NO "EAP Mitigation".
MIN=15; SPEED=0
for a in "$@"; do case $a in --speed) SPEED=1;; <->) MIN=$a;; esac; done
L=/usr/bin/log   # zsh's own "log" builtin shadows the macOS tool
echo "## loaded driver: $(kmutil showloaded --list-only 2>/dev/null | grep -oE 'com.flxxxxddd.AirportMtkWlan \([0-9.]+\) [0-9A-F-]+')"
echo "## en4: $(ifconfig en4 | awk '/status|inet /{printf "%s %s  ", $1, $2}')"
echo "## WCL timeline, last $MIN min (join / key-done / IPv4 / leave reasons)"
$L show --last ${MIN}m --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "initWCLJoinRequest" OR eventMessage CONTAINS "handleKeyDone" OR eventMessage CONTAINS "assocTimerAction" OR eventMessage CONTAINS "leaveNetworkCommand" OR eventMessage CONTAINS "Recived ipv4" OR eventMessage CONTAINS "EAP Mitigation" OR eventMessage CONTAINS "JOIN_MANAGER_EVENT_JOIN_CONNECT_COMPLETE moved")' 2>/dev/null |
  sed -nE 's/^[0-9-]+ ([0-9:.]{8}).*\] (initWCLJoinRequest|handleKeyDone|assocTimerAction|leaveNetworkCommand|ipStatusCommon|ipStatusInWaitForIp|logTransition)@[0-9]+:(.*)/\1 \3/p' |
  sed -E 's/WCLJoinRequest: lowerAuth = [A-Z_]+, upperAuth = AUTHTYPE_/JOIN /; s/, key = CIPHER_([A-Z]+) *, Valid Private Mac Addr \./ (key \1)/; s/FSM JOIN_MANAGER: .*/connect complete/; s/ isAbortJoin.*//'
echo "## airportd IPv4 programming (expect no 'offloads disabled' with the new kext)"
$L show --last ${MIN}m --style compact --predicate 'process == "airportd" AND eventMessage CONTAINS "_processIPv4Changes"' 2>/dev/null | grep -E 'offload|IPV4|Unable' | sed -nE 's/^[0-9-]+ ([0-9:.]{8}).*_processIPv4Changes: (.*)/\1 \2/p' | sort -u -k2 | tail -5
echo "## driver log (supplicant event / 802.1X data path / stats)"
X=$(mktemp); ioreg -r -c IOPCIDevice -k MtkDebugLog -a > "$X" 2>/dev/null
plutil -extract 0.MtkDebugLog raw -o - "$X" 2>/dev/null | grep -E 'supplicant done|setEnterpriseDataPath|WCL join|Deauth received|stats rx_hwdec|rxrate|tx txwi' | tail -14
rm -f "$X"
if [ $SPEED = 1 ]; then echo "## networkQuality on en4"; networkQuality -I en4 -s 2>&1 | tail -8; fi
