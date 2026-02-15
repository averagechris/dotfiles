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
| `Super+Scroll` | Scroll through workspaces |

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

### Keybindings help not opening

Verify the script is in your PATH:
```bash
which hyprland-keybindings-help
```

### Window rules not applying

Use `hyprctl clients` to check window class names, then update rules accordingly.
