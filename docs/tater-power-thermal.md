# tater Power and Thermal Tuning

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
