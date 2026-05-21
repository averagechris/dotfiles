# Tater Desktop Testing

This document describes the automated and semi-automated checks for tater's Hyprland desktop, greeter, Eww bar, fingerprint, and Wi-Fi setup.

## Static checks

The tater host flake exposes a desktop regression check:

```bash
nix flake check ./flakes/hosts/tater
```

This includes `checks.x86_64-linux.tater-desktop-static`, which is intentionally layered:

| Layer | What it checks | Why |
|-------|----------------|-----|
| Script correctness | Eww scripts pass `bash -n` and `shellcheck` | Shell mistakes can break the bar even when Nix evaluates cleanly. |
| Known-bad tripwires | Previously observed greeter breakages like `hyprtcl` and fragile GTK CSS constructs | These are narrow regression guards, not broad style rules. |
| Evaluated Nix invariants | Final merged options for greetd/ReGreet, fprintd/PAM, NetworkManager+iwd, logind lid behavior, Hyprland, kanshi, hypridle, and hyprlock | These test actual configuration values instead of grepping source layout. |
| Integration tripwires | Eww bar/window names, monitor-name bindings, per-monitor workspace script calls, helper command names, fingerprint hint copy | These names connect separate tools; if the desktop policy changes, update these few tripwires with the new integration contract. |

The check deliberately avoids trying to prove every visual policy. Things like exact workspace policy, monitor preference, and bar layout can change over time; only the durable safety contracts and known pain points should become hard failures.

For a narrower run:

```bash
nom build ./flakes/hosts/tater#checks.x86_64-linux.tater-desktop-static
```

## Runtime doctor

After rebuilding and logging into Hyprland on tater, run:

```bash
tater-desktop-doctor
```

The doctor checks the live system state:

- Hyprland IPC is reachable.
- `hypridle`, `kanshi`, `greetd`, NetworkManager, and iwd are active where expected.
- `/etc/greetd/environments` lists Hyprland so ReGreet launches the intended
  user session after successful authentication instead of bouncing back to the
  greeter.
- Fingerprint service plumbing is available.
- Wi-Fi is connected and the `mt7925e` driver is loaded.
- The home Dell U4320Q is detected on `DP-2` at `3840x2160` scale `1` when connected.
- Workspaces are on the expected displays when they exist.
- Eww bars are open for the enabled displays.

Warnings are for context-sensitive state, such as the Dell not being connected or a workspace not existing until visited. Failures indicate things that are expected to work in the current session.

## Related recovery commands

Display layout commands:

```bash
tater-home-clamshell  # Dell only, eDP-1 disabled
tater-home-open       # Dell + laptop panel
tater-home-toggle     # Toggle the two layouts and refresh Eww bars
```

Wi-Fi recovery command:

```bash
tater-network-recover
```

Use `tater-network-recover` when the MT7925e card wedges or NetworkManager stops reconnecting cleanly. It tries increasingly disruptive recovery steps before reloading the driver stack.

## Profile-size policy

Tater is a dev laptop, not a gaming or Openclaw node host. Keep the system
closure lean by avoiding host-local heavyweight packages that are not actively
used there:

- Steam, GameMode, and 32-bit graphics support are disabled on tater.
  The nixos-hardware AMD GPU profile enables 32-bit Mesa by default, so tater
  overrides that explicitly because it does not use Steam/Wine workloads.
- Openclaw node/gateway tooling is not imported on tater unless it is needed
  again for active laptop-side testing.
- Ghostty is the selected terminal. The shared GUI module does not install
  additional terminal emulators by default.
- Firefox is not part of the shared GUI defaults; browser usage is through Zen
  installed outside this host profile and Helium from Home Manager.
- Darktable is opt-in rather than part of the shared GUI defaults.

When auditing profile size, start with:

```bash
nix path-info -Sh /run/current-system
nix path-info --json -r /run/current-system
```
