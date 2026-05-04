# Hyprland Window Manager

This document describes the Hyprland window manager configuration, keybindings, and features.

## Overview

Hyprland is a modern Wayland compositor with GPU acceleration, smooth animations, and a flexible configuration system. This configuration uses Colemak Mod-DH navigation keys (M=Left, N=Down, E=Up, I=Right).

## Keybindings

### Core Window Management

| Key | Action |
|-----|--------|
| `Super+T` | Open terminal (configured in `dotfiles.gui.terminal`) |
| `Super+Q` | Close active window |
| `Super+Shift+Q` | Exit Hyprland |
| `Super+F` | Toggle fullscreen |
| `Super+Shift+F` | Toggle floating |
| `Super+Shift+P` | Pin window (floats on all workspaces) |
| `Super+Space` | Application launcher (anyrun) |

### Window Navigation (Colemak-DH)

| Key | Action |
|-----|--------|
| `Super+M` | Focus left |
| `Super+N` | Focus down |
| `Super+E` | Focus up |
| `Super+I` | Focus right |
| `Super+Shift+M` | Swap window left |
| `Super+Shift+N` | Swap window down |
| `Super+Shift+E` | Swap window up |
| `Super+Shift+I` | Swap window right |

### Workspaces

| Key | Action |
|-----|--------|
| `Super+1-9` | Switch to workspace 1-9 |
| `Super+0` | Switch to workspace 10 |
| `Super+Shift+1-9` | Move window to workspace 1-9 |
| `Super+Shift+0` | Move window to workspace 10 |
| `Super+Alt+M` | Previous workspace |
| `Super+Alt+I` | Next workspace |
| `Super+O` | Open the workspace overview / move menu |
| `Super+Scroll` | Scroll through workspaces |

### Workspace Overview

`Super+O` opens the script-backed workspace overview / move menu. This fallback is intentionally used on tater while Hyprspace is disabled: after reboot, Hyprland can start without the plugin dispatcher (`overview:toggle`), and the plugin path has been unstable enough to trigger Hyprland safe mode.

Hyprspace remains available as an option in the shared module for future retesting. If re-enabled, it must be compiled against the exact active Hyprland build because Hyprland plugins depend on internal compositor headers. Update Hyprland and Hyprspace together and verify a full tater system build before enabling it again.

| Action | Behavior |
|--------|----------|
| `Super+O` | Open the workspace overview / move menu |
| Select a workspace | Switch to that workspace |
| Select a move target while a window is focused | Move the focused window to that workspace |
| `Escape` | Close the menu |

### Submaps (Modal Modes)

Submaps provide modal keybindings. Press `Super+<key>` to enter, `Escape` to exit.

#### Quick Actions (`Super+A`)

| Key | Action |
|-----|--------|
| `s` | Focus or launch Signal |
| `t` | Focus or launch Telegram |
| `k` | Focus or launch KeePassXC |
| `b` | Focus or launch Zen browser |
| `o` | Focus or launch Obsidian |
| `l` | Lock screen (hyprlock) |
| `p` | Open Pavucontrol (audio) |
| `c` | Color picker (hyprpicker) |
| `d` | Toggle notification center |
| `w` | Toggle eww bar |
| `z` | Toggle eww bar (alternate) |
| `y` | Toggle QWERTY/Colemak-DH layout |
| `h` or `?` | Show keybindings help |
| `Escape` | Exit submap |

#### Resize Mode (`Super+R`)

| Key | Action |
|-----|--------|
| `M` | Shrink width |
| `N` | Grow height |
| `E` | Shrink height |
| `I` | Grow width |
| `Escape` | Exit resize mode |

#### Scratchpad Mode (`Super+S`)

| Key | Action |
|-----|--------|
| `t` | Toggle terminal scratchpad |
| `Shift+T` | Move window to terminal scratchpad |
| `s` | Toggle general scratchpad |
| `Shift+S` | Move window to general scratchpad |
| `Escape` | Exit submap |

### Special Workspaces

| Key | Action |
|-----|--------|
| `` Super+` `` | Toggle terminal scratchpad |
| `Super+Shift+`` | Move window to terminal scratchpad |
| `Super+Escape` | Return to previous workspace |

### Screenshots

| Key | Action |
|-----|--------|
| `Print` | Screenshot area (copy + save) |
| `Shift+Print` | Screenshot output/monitor (copy + save) |
| `Super+Print` | Screenshot active window (copy + save) |

### Media & System

| Key | Action |
|-----|--------|
| `XF86AudioMute` | Toggle mute |
| `XF86AudioRaiseVol` | Volume up |
| `XF86AudioLowerVol` | Volume down |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |
| `XF86AudioPlay` | Play/Pause |
| `XF86MonBrightness+` | Brightness up |
| `XF86MonBrightness-` | Brightness down |
| `Super+Shift+Ctrl+Alt+Space` | Toggle QWERTY/Colemak-DH layout (mega keychord) |

## Lock Screen (Hyprlock)

The lock screen displays a blurred screenshot of your desktop with an overlay. Key features:

- **Time and date** displayed prominently at the top
- **Password input** with asterisks (`*`) for better visibility
- **Now playing** info (when music is playing)
- **Fingerprint auth** when fprintd + PAM are enabled for hyprlock
- **Fingerprint hint text** so laptop unlock makes it clear that touching the sensor and typing the password are both valid paths.

> **Note:** Since you use multiple keyboard layouts (Colemak-DH and QWERTY), typos can be confusing. The password field shows asterisks (`*`) instead of dots for better visibility.
>
> **Keyboard layout:** Layout switching does not work inside hyprlock (it's a secure lock screen). Make sure you're typing with the correct layout before locking. The Colemak-DH/QWERTY toggle (Shift+Space) only works when Hyprland is running, not during authentication.

### Activating the Lock Screen

| Method | Action |
|--------|--------|
| `Super+A, l` | Lock via Quick Actions submap |
| Close laptop lid | Auto-lock (if configured) |
| Idle timeout | Auto-lock via hypridle |

### Fingerprint authentication

If the host enables `fprintd` and fingerprint auth is configured, you can unlock with either fingerprint or password. In this setup:

- **Hyprlock** uses Hyprlock's `auth.fingerprint.enabled` for parallel fingerprint auth (keeps PAM password fallback via `unixAuth`).
- **ReGreet** (login/greeter session) uses lid-aware PAM fingerprint auth on tater. When the lid is open, fingerprint login is available. When the lid is closed, a small `pam_exec` guard skips `pam_fprintd` so clamshell login immediately falls back to password entry instead of waiting on an inaccessible fingerprint sensor.

Password entry remains available; ensure the PAM service enables `unixAuth` for password fallback when needed.

`sudo` intentionally uses password-first authentication on tater. In clamshell mode the ThinkPad fingerprint sensor is physically unavailable, and PAM fingerprint auth blocks password entry until the sensor attempt times out. Disabling `security.pam.services.sudo.fprintAuth` makes terminal elevation prompt for the password immediately while keeping fingerprints for login and lock-screen flows.

On ThinkPads with Goodix sensors, enable the libfprint TOD driver (e.g. `services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;`).

## Idle & Locking

Hyprland uses **hypridle** for idle timeouts and **hyprlock** for locking. The Hypridle module exposes timeout settings so you can tune lock and power behavior for laptops.

The dim action is **relative to your current brightness** (it never increases brightness), so late-night low-brightness sessions won't be bumped up by the idle dim.

### Hypridle timeout options

| Option | Purpose |
|--------|---------|
| `dotfiles.hypridle.timeouts.dim` | Seconds before dimming the screen |
| `dotfiles.hypridle.timeouts.lock` | Seconds before locking the session |
| `dotfiles.hypridle.timeouts.dpms` | Seconds before turning off displays |
| `dotfiles.hypridle.timeouts.suspend` | Seconds before suspending (set `0` to disable) |
| `dotfiles.hypridle.timeouts.hibernate` | Seconds before hibernating (set `0` to disable) |

### Suggested laptop timings

For a battery-friendly setup:

```nix
dotfiles.hypridle.timeouts = {
  dim = 120;       # 2 minutes
  lock = 300;      # 5 minutes
  dpms = 360;      # 6 minutes
  suspend = 420;   # 7 minutes
  hibernate = 1200; # 20 minutes
};
```

> Note: hibernate requires working swap. If hibernation is not configured, set `hibernate = 0` and use `suspend` instead.

## Laptop, Docking, and External Monitors

The shared Hyprland config has conservative monitor defaults:

| Output | Default behavior |
|--------|------------------|
| `eDP-1` | Preferred mode, automatic position, scale `1` unless the host overrides it |
| Any other monitor | Preferred mode, automatic position, scale `1` |

On tater, `kanshi` adds host-specific docking profiles:

| Profile | Behavior |
|---------|----------|
| `undocked` | Use the ThinkPad panel at `1920x1200@60Hz`, scale `1.5` |
| `home-dell-43-*` | Preferred home clamshell mode for the exact `Dell Inc. DELL U4320Q 1LTJW13` and known/likely Dell 43" model strings: disable `eDP-1` and use the Dell at `3840x2160@60Hz`, scale `1.0` |
| `docked-wildcard` | Generic fallback for unknown monitors: keep the laptop panel enabled below the external monitor and place the external display to the right at scale `1.0` |

Tater also provides manual home layout commands for when you want to override the automatic clamshell preference without editing the Nix config:

| Command | Behavior |
|---------|----------|
| `tater-home-clamshell` | Home Dell only: `DP-2` at `3840x2160@60Hz`, disable `eDP-1` |
| `tater-home-open` | Home Dell plus laptop panel: Dell at `3840x2160@60Hz`, laptop panel enabled below/left at `1920x1200@60Hz`, scale `1.5` |
| `tater-home-toggle` | Toggle between the two layouts above and send a desktop notification |

Use `tater-home-open` after opening the lid if you want the internal display on as a secondary panel while still using the 43" Dell as the main workspace area.

When the Dell is connected on tater, the Eww bar shows a display toggle next to the keyboard indicator:

| Indicator | Meaning |
|-----------|---------|
| `󰍹` | Dell-only clamshell mode; click to enable the laptop panel |
| `󰌢+󰍹` | Dell plus laptop panel; click to return to Dell-only clamshell |

The Eww bar opens by monitor name on both displays when both are active. Workspace buttons are monitor-local:

| Monitor | Workspaces |
|---------|------------|
| Home Dell (`DP-2`) | `1`-`5` |
| Laptop panel (`eDP-1`) | `6`-`10` |

When the laptop panel is disabled, the internal-display bar closes with that output and the Dell bar remains active. Lid-close/open and the tater home display toggle both refresh Eww bars after changing monitors, so the panel should not get stranded on the wrong output.

Lid handling is split between systemd-logind and Hyprland:

- On battery with no dock, logind may still suspend on lid close.
- On external power or with a dock/display, logind ignores the lid so clamshell mode can work.
- Hyprland disables `eDP-1` on lid close when another monitor is present, but does not lock in that docked/clamshell case. If no external monitor is connected, lid close still locks before the normal logind suspend path.
- The tater home Dell profiles also disable `eDP-1` declaratively in kanshi, so closing the lid at home leaves only the 43" monitor active.
- Opening the lid re-enables `eDP-1` and wakes displays with DPMS.

The greetd/ReGreet Hyprland session has its own early display fix because user-level kanshi is not running at the login screen. During greetd startup, if the lid is closed and any external monitor is present, the greeter disables `eDP-*` so ReGreet is forced onto the visible docked display instead of rendering only on the built-in panel.

If a particular monitor needs exact refresh/scale/position, add a more specific tater `services.kanshi.settings` profile using the monitor model/serial from `hyprctl monitors`.

## Application Integration

### Signal

- Auto-starts on login with `--start-in-tray`
- Opens on workspace 9 silently
- Main window floats at 1000x700 centered
- Key: `Super+A, s` to focus/launch

### Telegram

- Opens on workspace 9 silently  
- Main window floats at 1000x700 centered
- Key: `Super+A, t` to focus/launch

### KeePassXC

- Floats and centers at 900x600
- Unlock dialog is pinned
- Key: `Super+A, k` to focus/launch

## Window Rules

See `windowrules.nix` for detailed window behavior configuration:

- **Picture-in-Picture**: Floats, pinned, positioned bottom-right
- **MPV**: Floats at 960x540 centered
- **Steam games**: Fullscreen, immediate rendering
- **Pavucontrol**: Floats at 800x600 centered
- **File dialogs**: Float at 800x600 centered
- **Calculator**: Floats at 400x500
- **Image viewer (imv)**: Floats at 80% size centered

## Submap Indicator

The eww bar displays the current submap with a pulsing gold indicator:
- **󰩨 RESIZE** - Resize mode
- **󰗼 SCRATCH** - Scratchpad mode
- **󰍜 ACTIONS** - Quick actions mode

## Keybindings Help

Press `Super+A` then `h` or `?` to display a comprehensive cheat sheet of all keybindings in a floating terminal window.

## Configuration Files

| File | Purpose |
|------|---------|
| `default.nix` | Main configuration, keybindings, settings |
| `windowrules.nix` | Window-specific rules and behaviors |
| `animations.nix` | Animation settings and curves |
| `waybar.nix` | Status bar configuration |
| `theme.nix` | Visual theming |
| `gestures.nix` | Touchpad gesture configuration |
| `wallpaperd.nix` | Wallpaper management |
| `scripts/keybindings-help.sh` | Help viewer script |

## Troubleshooting

### Submap not showing in eww bar

Ensure `socat` is installed and the submap script is executable:
```bash
chmod +x ~/.config/eww/scripts/submap.sh
```

### Eww commands cannot connect to the daemon

The home-manager Eww module installs an `eww` wrapper that normalizes
`XDG_RUNTIME_DIR` and `XDG_CONFIG_HOME` before invoking Eww, and points commands
at `~/.config/eww-stable`. Eww derives its IPC socket from those values plus the
canonical config directory, so a missing/different environment or a
generation-specific Home Manager config symlink can make `eww state`,
`eww active-windows`, and other CLI commands look for a different daemon than the
Hyprland-started bar is using.

If commands still cannot connect after switching to the updated configuration,
restart the user daemon once from inside Hyprland:

```bash
eww kill
eww daemon
eww-open-bars
```

### Keybindings help not opening

Verify the script is in your PATH:
```bash
which hyprland-keybindings-help
```

### Window rules not applying

Use `hyprctl clients` to check window class names, then update rules accordingly.
