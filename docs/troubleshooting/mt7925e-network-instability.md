# MT7925e Wi-Fi instability on tater

## Symptoms

- Wi-Fi randomly disconnects or stops passing traffic
- NetworkManager may crash or stay running while the laptop cannot reconnect cleanly
- Tailscale, DNS, or other network-dependent services start timing out afterward
- The system often seems recoverable only after a reboot

This has been observed on `tater`, which uses a MEDIATEK MT7925 wireless card with the `mt7925e` kernel driver.

## Likely Cause

This appears to be primarily a driver and/or firmware stability issue. NetworkManager may be the visible failure point, but the underlying trigger can still be a wedged `mt7925e`/`mt76` driver or firmware state.

Relevant factors:

- MT7925 / `mt7925e` is still relatively new on Linux
- Stability can vary across kernel and `linux-firmware` versions
- Power saving, roaming, suspend/resume, or higher-band operation (especially 6 GHz) may contribute

On `tater`, the host configuration uses a conservative stability profile in `flakes/hosts/tater/configuration.nix`:

```nix
boot.kernelPackages = pkgs.linuxPackages_latest;
networking.networkmanager.wifi.backend = "iwd";
networking.networkmanager.wifi.powersave = false;
networking.wireless.iwd.enable = true;
hardware.wirelessRegulatoryDatabase = true;
systemd.services.NetworkManager.serviceConfig.Restart = "always";

services.tlp.settings = {
  WIFI_PWR_ON_AC = "off";
  WIFI_PWR_ON_BAT = "off";
};
```

Keep these mitigations in place until the host remains stable across newer `nixpkgs`, `linux-firmware`, and platform firmware updates. If the system is stable for a meaningful period, back these out one at a time rather than all at once so regressions are attributable.

## Immediate Recovery (Without Reboot)

Try these in order.

### 0. Use the packaged recovery helper

The `tater` home configuration installs a helper that captures relevant status/logs, then tries the recovery sequence below:

```bash
tater-network-recover
```

If the Wi-Fi interface name changes, pass it explicitly:

```bash
tater-network-recover <interface>
```

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
iwctl device list
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
systemctl --no-pager status iwd NetworkManager
```

If the system remains stable for a meaningful period across battery use, suspend/resume, and normal roaming, retest by removing one mitigation at a time. Suggested order:

1. Remove `systemd.services.NetworkManager.serviceConfig.Restart` if NetworkManager is no longer crashing.
2. Switch NetworkManager back from `iwd` to the default `wpa_supplicant` backend if association is stable.
3. Re-enable NetworkManager Wi-Fi powersave.
4. Re-enable TLP Wi-Fi powersave on battery.
5. Return from `linuxPackages_latest` to the default kernel once MT7925e fixes are in the default kernel.

## Related Files

- `flakes/hosts/tater/configuration.nix` - host-specific MT7925e stability profile and `tater-network-recover` helper
- `docs/README.md` - documentation index
