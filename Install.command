#!/bin/bash
# Double-click in Finder to install this OpenCore EFI on the G513RM's EFI partition.
# It asks for your password, shows what will change, and asks again before writing.
cd "$(dirname "$0")" || exit 1
clear
echo "ASUS ROG Strix G15 (G513RM) - OpenCore EFI installer"
echo
/bin/bash ./scripts/install.sh "$@"
status=$?
echo
read -r -p "Press Return to close this window. " _
exit $status
