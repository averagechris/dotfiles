# tater power and thermal tuning

`tater` is a ThinkPad T14s Gen 5 AMD. Its power policy is intentionally tuned
for a quieter laptop profile while preserving responsive plugged-in desktop use.

## Current policy

The host enables TLP in `flakes/hosts/tater/configuration.nix` and keeps
`power-profiles-daemon` disabled so there is a single power-management owner.

Relevant TLP settings:

| Setting | AC | Battery | Reason |
| --- | --- | --- | --- |
| CPU governor | `schedutil` | `powersave` | Avoid pinning plugged-in use to the hottest `performance` governor while still scaling quickly under load. |
| CPU energy/performance policy | `balance_performance` | `power` | Keep AC responsive and battery conservative. |
| Platform profile | `balanced` | `low-power` | Ask the ThinkPad firmware for a less aggressive thermal/fan profile. |
| CPU boost | default/enabled | disabled | Keep AC bursts fast, but reduce battery heat and fan ramping. |
| Wi-Fi power save | off | off | Required for the MT7925e stability mitigation documented in `docs/troubleshooting/mt7925e-network-instability.md`. |

`services.thermald.enable = true` remains enabled as an additional thermal
management layer.

## Idle, lock, and sleep policy

`tater` uses Hypridle + Hyprlock for session idling. The host keeps the
conservative laptop/travel timers when the machine is undocked, using the laptop
panel, or docked somewhere other than the known home display:

| Action | Laptop / travel timeout |
| --- | ---: |
| Dim panel | 2 minutes |
| Lock session | 5 minutes |
| Turn displays off | 6 minutes |
| Suspend, then hibernate | 7 minutes |
| Direct hibernate fallback while still awake | 20 minutes |

Home clamshell mode is detected by `tater-home-docked`, which checks Hyprland for
one of the known home Dell monitors on `DP-2` (`DELL U4320Q`, `DELL U4323QE`, or
`DELL P4317Q`) and verifies that the internal `eDP-1` panel is not enabled. In
that posture, Hypridle keeps the quick laptop timers from firing and uses a more
desktop-like policy instead:

| Action | Home clamshell timeout |
| --- | ---: |
| Dim panel | 2 minutes |
| Lock session | 10 minutes |
| Turn displays off | 11 minutes |
| Suspend, then hibernate | 1 hour |
| Direct hibernate fallback while still awake | disabled by the home-clamshell guard |

The suspend action uses `systemctl suspend-then-hibernate`, with systemd sleep
configured for `HibernateDelaySec=1h`. This matters for travel: if the laptop is
already suspended and then gets unplugged and put into a bag without opening the
lid or logging in, the user Hypridle timers are no longer running, but systemd's
wake timer should still wake the machine after one hour of suspend and transition
it to hibernate for better battery conservation.

Hibernation resumes from a 40 GiB `/swapfile` inside the encrypted ext4 root
filesystem. This keeps RAM images encrypted at rest by the root LUKS container
without requiring a second unlock prompt. The old disko swap partition remains
random-encrypted and is intentionally unused for resume because its key changes
every boot.

The resume settings live in `flakes/hosts/tater/hardware.nix`:

```nix
boot.resumeDevice = "/dev/disk/by-uuid/e817895a-ef3f-4289-8c9e-7e4e49703b13";
boot.kernelParams = ["resume_offset=13852672"];
swapDevices = lib.mkForce [{ device = "/swapfile"; size = 40960; }];
zramSwap.enable = lib.mkForce false;
```

### Swapfile resume offset

`resume_offset` is the physical disk block where the swapfile starts. The kernel
needs it because `/swapfile` is a file inside ext4, not a whole swap partition;
early resume happens before the normal root filesystem is fully mounted and
before the kernel can ask ext4 to look up the file by path.

The current offset was calculated on `tater` after creating `/swapfile`:

```bash
sudo install -o root -g root -m 0600 /dev/null /swapfile
sudo fallocate -l 40G /swapfile
sudo mkswap /swapfile
sudo filefrag -v /swapfile | awk '/^[ ]*0:/{print $4}' | tr -d .
```

The expected output is:

```text
13852672
```

If `/swapfile` is deleted, recreated, moved, resized, or defragmented, this value
can change. Recalculate the offset, update `boot.kernelParams`, rebuild, and
reboot before relying on hibernation again. A quick verification command is:

```bash
sudo filefrag -v /swapfile | awk '/^[ ]*0:/{print $4}' | tr -d .
```

After booting a generation with hibernation enabled, verify the active kernel
command line contains both resume parameters:

```bash
cat /proc/cmdline | tr ' ' '\n' | grep '^resume'
```

Expected values:

```text
resume=/dev/disk/by-uuid/e817895a-ef3f-4289-8c9e-7e4e49703b13
resume_offset=13852672
```

Operational rules:

- Do not delete or recreate `/swapfile` without updating `resume_offset`.
- Do not defragment `/` while relying on swapfile resume.
- After kernel/NixOS upgrades, prefer a clean reboot before testing hibernate.
- If hibernate powers off but resumes to a fresh boot, check the offset first.

### Temporary idle inhibit

The Eww bar shows an idle-inhibit button on `tater`:

| Icon | State | Action |
| --- | --- | --- |
| `󰾪` | Idle automation is normal | Click to inhibit automatic dim, lock, display-off, suspend, and hibernate. |
| `󰅶` | Idle automation is inhibited | Click to clear the inhibit manually. |

The shared helper is `dotfiles-idle-inhibit`. It stores the inhibit only for the
current runtime posture, represented by AC power state, lid state, and active
Hyprland monitor layout. If any of those change, such as plugging in,
unplugging, opening or closing the lid, or changing dock/display state, the next
status check automatically clears the inhibit and normal Hypridle policy resumes.
This makes it useful for "keep this long task running while I walk around"
without accidentally carrying the no-lock state into travel or clamshell use.

Useful runtime checks:

```bash
tater-home-docked && echo home-clamshell || echo laptop-or-away
dotfiles-idle-inhibit status
dotfiles-idle-inhibit toggle
systemctl --user status hypridle.service
systemctl suspend-then-hibernate
systemctl hibernate
```

## Iteration notes

If fans are still too loud on AC, try these in order:

1. Change `CPU_ENERGY_PERF_POLICY_ON_AC` from `balance_performance` to
   `balance_power`.
2. Add `CPU_BOOST_ON_AC = 0;` if quiet operation matters more than short burst
   performance.
3. Consider a ThinkPad-specific fan controller such as `thinkfan` only after the
   firmware/platform-profile/TLP knobs are exhausted. Fan-control daemons are
   more invasive and need careful sensor mapping.

Useful runtime checks on tater:

```bash
sudo tlp-stat -p
sudo tlp-stat -t
cat /sys/firmware/acpi/platform_profile
cat /sys/firmware/acpi/platform_profile_choices
```

After changing the Nix config, rebuild with:

```bash
sudo nixos-rebuild switch --flake .#tater
```
