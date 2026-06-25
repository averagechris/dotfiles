# Home-Manager Activation Timeout

## Symptoms

- `nixos-rebuild switch` hangs at "Activating reloadSystemd"
- `home-manager-chris.service` times out after 5 minutes
- Logs show services being started but never completing:
  ```
  Starting units: blueman-applet.service, waybar.service, hyprpaper.service, ...
  ```

## Root Cause

Home-manager's `systemd.user.startServices` defaults to `true` (as of 25.05+), which uses `sd-switch` to synchronously start/restart user systemd services during activation.

GUI services like waybar, hyprpaper, and blueman-applet require a display server (`WAYLAND_DISPLAY` or `DISPLAY`) to function. When running `nixos-rebuild switch` from a TTY or SSH session, these environment variables aren't set, so the services hang waiting for a display that doesn't exist.

## Solution

Use `RefuseManualStart = true` on GUI services. This tells `sd-switch` to skip them during activation while still allowing them to start normally via `WantedBy=graphical-session.target` on login.

```nix
home-manager.users.chris = {config, lib, ...}: let
  # GUI services that require a display and will hang during activation
  guiServicesToSkip = [
    "blueman-applet"
    "hyprpaper"
    "hypridle"
    "hctl"
    "waybar"
    "swaync"
    "network-manager-applet"
    "udiskie"
    "mako"
    "gammastep"
    "swayidle"
    "com.mitchellh.ghostty"
    "mega-cmd-server-init"
  ];
  mkSkipDuringActivation = name: lib.nameValuePair name {
    Unit.RefuseManualStart = lib.mkForce true;
  };
in {
  # Keep service restarts enabled for non-GUI services
  systemd.user.startServices = true;
  systemd.user.services = lib.listToAttrs (map mkSkipDuringActivation guiServicesToSkip);
  # ...
};
```

## How It Works

| Service Type | During Activation | On Login |
|--------------|-------------------|----------|
| GUI services | **Skipped** (no hang) | Start via `graphical-session.target` |
| Other services | **Restart normally** | Already running |

Because GUI services are skipped during activation, changes to them only take effect on the next login. To apply an updated unit or package immediately, **log out and back in** so `graphical-session.target` restarts them. `systemctl --user restart <service>` is often blocked by `RefuseManualStart` and is not reliable for these services.

## Alternative Approaches (and why they don't work)

### `ConditionEnvironment`

```nix
Unit.ConditionEnvironment = "WAYLAND_DISPLAY";
```

**Why it doesn't work**: `sd-switch` still waits synchronously for services to reach their target state, even if the condition causes them to be skipped.

### `startServices = false`

```nix
systemd.user.startServices = false;
```

**Why it's not ideal**: Prevents ALL services from restarting during activation, including ones that would work fine (like ssh-agent). You'd need to manually restart services or log out/in after every switch.

## Debugging Tips

1. Check which services are being started:
   ```bash
   journalctl --user -u home-manager-chris.service -n 100
   ```

2. Verify RefuseManualStart is set:
   ```bash
   grep RefuseManualStart ~/.config/systemd/user/*.service
   ```

3. Check the activation script:
   ```bash
   cat /nix/store/<hash>-home-manager-generation/activate | grep -A 50 reloadSystemd
   ```

## Related Issues

- Home-manager 25.05 changed `startServices` default from `false` to `true`
- The `sd-switch` tool is used when `startServices = true`
- GUI services typically have `WantedBy = graphical-session.target`
