# MT7922 Wi-Fi (AirportMtkWlan)

`EFI/OC/Kexts/AirportMtkWlan.kext` is [flxxxxddd/SimpleMtkWlan](https://github.com/flxxxxddd/SimpleMtkWlan) v1.5.0
(commit `9a9c2ea`), Debug build for macOS Tahoe, with `src/wifi/mtk-fixes.patch` and the MT7922 firmware from
linux-firmware 20260724 (`src/wifi/firmware/`). It shows up as normal Wi-Fi in the menu bar (IO80211 / Skywalk).
Rebuild it with `bash src/wifi/build.sh`.

## What the patch changes

**WPA2-Enterprise / 802.1X (eduroam, university networks)**. Status: confirmed working.

- Every 802.1X join used to drop about 15 s after association with `assocTimerAction: no key/4way hand shake event`
  (`4wayHsTimeout`). IO80211's WCL only clears that deadline when the driver posts the supplicant event (message 76)
  after the four-way handshake, and the driver never posted it. It does now.
- The driver now advertises the ARP/NDP-offload capability (bit 40) and accepts `IPV4_PARAMS`. Without it airportd
  never told WCL the DHCP address, so WCL started "EAP Mitigation" and reassociated.
- The 802.1X data path opens at association, so EAPOL frames can flow before the keys are set.

**Throughput**

- Data frames are no longer sent at the basic rate when Block Ack is off (upstream PR #1).
- DMA uses cached packet bounce buffers (upstream PR #2).
- Background scans use the firmware's default dwell time per channel instead of 120 ms.

**Warm reboot** (v3, 2026-11-03). Status: built, not yet confirmed on this laptop.

A warm reboot (restart, or switching from Pop!_OS / Windows without powering off) doesn't cut power to the M.2 card,
so the card still holds the firmware patch the previous OS loaded. The driver read the patch semaphore's
"already downloaded" reply (`PATCH_IS_DL`) as an error and never loaded the main (WM) firmware. Without firmware there
is no MAC address, so the Wi-Fi controller stopped about 2.5 s into boot and macOS showed no Wi-Fi at all. Fixes:

- `PATCH_IS_DL`: skip the patch and load only the WM firmware, as Linux `mt76_connac2_load_patch()` does.
- Hardware init is retried up to 3 times. Each failed attempt ends with a DMA + WFSYS reset.
- On restart / shutdown (`systemWillShutdown`) the driver takes ownership of the chip, stops DMA and resets WFSYS, so
  the next OS finds a clean chip. This hook only writes registers and sends no firmware commands, so it can't stall
  shutdown.

## Checking it

```sh
zsh tools/wifi-verify.sh        # last 15 min: joins, key-done events, IPv4, leave reasons (add --speed for a speed test)
sh tools/mtklog.sh              # the driver's own log; works even if the Wi-Fi controller failed to start
```

A good 802.1X join reads, in order: `JOIN 8021X` → `supplicant done (driver)` → `IO80211RSNDone set=<1>` →
`ipv4 valid = <1>`, with no `4wayHsTimeout` and no `EAP Mitigation`.

After a warm reboot, `tools/mtklog.sh` should show `patch already downloaded (warm boot), loading WM only` and then
`firmware loaded and ready`. If Wi-Fi is missing after a restart, run `tools/mtklog.sh` **before** rebooting again.
The macOS system log has nothing from the driver, and its own log is lost on the next boot.

In Windows, turn off Fast Startup, which otherwise leaves the card half-initialised.
