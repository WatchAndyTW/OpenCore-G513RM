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
- **Noise floor** (2026-11-05). The driver reported 0 dBm noise, so macOS saw e.g. RSSI -43 dBm / noise 0 dBm, an
  SNR of -43 dB on an excellent link. macOS's link-quality and roaming logic run on that SNR (and macOS was scanning
  2.4 GHz every 12-100 s while connected on 5 GHz). The firmware doesn't measure noise, so the driver now reports the
  thermal noise floor for the channel width: -94 / -91 / -88 dBm at 20 / 40 / 80 MHz.
- **Upload latency** (2026-11-05). The driver kept its own unmanaged FIFO of up to 2048 frames between macOS and the
  256-slot TX ring, which defeats macOS's AQM (FQ-CoDel). `networkQuality` measured 3.7 s of uplink delay under load.
  The FIFO is now 256 frames, so the backlog waits in macOS's managed queue.
- Not changed yet: the firmware always gets the world regulatory domain (`00`) and a fixed 20 dBm per-rate power cap.
  Per-country power (the firmware's CLC tables, as Linux loads them) is not implemented.

**Warm reboot** (v3, 2026-11-03). Status: built, not yet confirmed on this laptop.

A warm reboot (restart, or switching from Pop!_OS / Windows without powering off) doesn't cut power to the M.2 card,
so the card still holds the firmware patch the previous OS loaded. The driver read the patch semaphore's
"already downloaded" reply (`PATCH_IS_DL`) as an error and never loaded the main (WM) firmware. Without firmware there
is no MAC address, so the Wi-Fi controller stopped about 2.5 s into boot and macOS showed no Wi-Fi at all. Fixes:

- `PATCH_IS_DL`: skip the patch and load only the WM firmware, as Linux `mt76_connac2_load_patch()` does.
- Hardware init is retried up to 3 times. Each failed attempt ends with a DMA + WFSYS reset.

**Wi-Fi dead after a restart *or* shutdown** (v4, 2026-11-05). Status: built, not yet confirmed on this laptop.

v3 still lost Wi-Fi on 3 boots on 2026-11-04 (19:45, 20:00, 21:25). Each one followed a clean Shut Down or Restart,
and every forced power-off was followed by a good boot. The M.2 card on this laptop keeps standby power across a
shutdown too, not just a restart. In each failed boot the IOPCIFamily log shows the same thing: the chip refused the
host/firmware ownership handshake (`LPCTL`) at attach, the driver fell through WFSYS reset to a PCIe FLR about 2.2 s into
boot, and the controller was torn down at 2.7 s. These failures never reached the patch download, so `PATCH_IS_DL`
was not involved. Fixes:

- **No more FLR.** The MT7922 advertises Function-Level Reset but it is broken: afterwards every config read returns
  all ones and the card stays dead until it loses power. Linux never FLRs this chip (`quirk_no_flr`, "PCI: Avoid FLR
  for Mediatek MT7922 WiFi") and falls back to a Secondary Bus Reset, which works. The driver now does the same, a hot
  reset of the link through the root port above the card (`GPP5`). It is skipped on hot-plug ports.
- **Shutdown hook.** v3 left the chip in driver ownership, freshly WFSYS-reset, with no firmware. That's an unusual
  state, and every failed boot followed a shutdown that ran this hook. v4 leaves the chip the way Linux suspend does:
  interrupts masked, DMA stopped, ownership handed back to the firmware, and PCI bus mastering off so the card can't
  DMA into the next OS's memory. The firmware keeps running, and the next boot takes the chip back and loads WM only
  (`PATCH_IS_DL`).
- **Logging.** On attach and at every recovery step the driver logs `lpctl`, `chipid`, the PCI command register,
  the vendor ID and the root port's link status. `lpctl=0xffffffff` means MMIO itself is dead, and any other value
  means the chip answers but won't hand over.

## Checking it

```sh
zsh tools/wifi-verify.sh        # last 15 min: joins, key-done events, IPv4, leave reasons (add --speed for a speed test)
sh tools/mtklog.sh              # the driver's own log; works even if the Wi-Fi controller failed to start
```

A good 802.1X join reads, in order: `JOIN 8021X` → `supplicant done (driver)` → `IO80211RSNDone set=<1>` →
`ipv4 valid = <1>`, with no `4wayHsTimeout` and no `EAP Mitigation`.

After a warm reboot, `tools/mtklog.sh` should show `patch already downloaded (warm boot), loading WM only` and then
`firmware loaded and ready`. If Wi-Fi is missing after a restart, run `tools/mtklog.sh` **before** rebooting again.
The macOS system log has nothing from the driver, its own log is lost on the next boot, and it is a ring buffer
that overwrites the boot-time lines after about 10 minutes of use.

To keep it automatically, install the login agent once:

```sh
sh tools/mtklog-autosave.sh --install     # no sudo; --uninstall removes it
```

At every login it saves the log to `~/Library/Logs/AirportMtkWlan/boot-<boot time>.log` and keeps the newest 30.
If the Wi-Fi controller didn't start, the file name ends in `-FAILED` and a notification appears. The lines that
matter are `attach state:`, `... trying WFSYS reset`, `... trying PCIe bus reset` and `SBR done` / `SBR: ...`.

In Windows, turn off Fast Startup, which otherwise leaves the card half-initialised.
