# MT7925e Wi-Fi instability on tater

## Symptoms

- Wi-Fi randomly disconnects or stops passing traffic
- NetworkManager stays running, but the laptop cannot reconnect cleanly
- Tailscale, DNS, or other network-dependent services start timing out afterward
- The system often seems recoverable only after a reboot

This has been observed on `tater`, which uses a MEDIATEK MT7925 wireless card with the `mt7925e` kernel driver.

## Likely Cause

This appears to be a driver and/or firmware stability issue rather than a full NetworkManager crash.

Relevant factors:

- MT7925 / `mt7925e` is still relatively new on Linux
- Stability can vary across kernel and `linux-firmware` versions
- Power saving, roaming, suspend/resume, or higher-band operation (especially 6 GHz) may contribute

On `tater`, Wi-Fi power saving on battery was disabled in `flakes/hosts/tater/configuration.nix` as a mitigation:

```nix
WIFI_PWR_ON_AC = "off";
WIFI_PWR_ON_BAT = "off";
```

Keep this mitigation in place until the host remains stable across newer `nixpkgs`, `linux-firmware`, and platform firmware updates.

## Immediate Recovery (Without Reboot)

Try these in order.

### 1. Bounce networking in NetworkManager

```bash
nmcli networking off
sleep 3
nmcli networking on
```

### 2. Reconnect the Wi-Fi device

```bash
nmcli device disconnect wlp194s0
sleep 3
nmcli device connect wlp194s0
```

### 3. Restart NetworkManager

```bash
sudo systemctl restart NetworkManager
nmcli general status
nmcli device status
```

### 4. Reload the MEDIATEK Wi-Fi driver

If the interface is wedged and the steps above do not recover it, reload the driver modules:

```bash
sudo modprobe -r mt7925e mt792x_lib mt76_connac_lib mt76
sleep 3
sudo modprobe mt7925e
sleep 3
nmcli device wifi rescan
nmcli device status
```

This is the most likely non-reboot recovery path if the underlying driver has wedged.

## What to Capture When It Breaks

As soon as the failure happens, collect the following before rebooting:

```bash
nmcli general status
nmcli device status
systemctl --no-pager --full status NetworkManager.service
journalctl -b --no-pager -u NetworkManager.service -n 200
journalctl -b --no-pager | rg -i "mt7925|mt76|wlp194s0|NetworkManager|firmware|timeout|reset|failed"
```

This helps distinguish between:

- a NetworkManager problem
- an authentication/reassociation failure
- a kernel driver reset or firmware hang
- a connectivity failure that only affects upper-layer services

## Verification After Rebuilds

After updating `nixpkgs`, `linux-firmware`, or system firmware, verify the current state:

```bash
nmcli -f GENERAL,WIFI-PROPERTIES device show wlp194s0
uname -a
fwupdmgr get-updates
```

If the system remains stable for a meaningful period across battery use, suspend/resume, and normal roaming, retest with Wi-Fi powersave re-enabled before removing the mitigation from `tater`.

## Related Files

- `flakes/hosts/tater/configuration.nix` - host-specific TLP Wi-Fi mitigation
- `docs/README.md` - documentation index
