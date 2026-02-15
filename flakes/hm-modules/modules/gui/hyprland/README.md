# Hyprland Window Manager Configuration

This module provides a modern Hyprland window manager setup for Wayland, featuring advanced animations, window rules, and comprehensive keybindings with Colemak Mod-DH support.

**📖 Full documentation**: See [docs/hyprland.md](/docs/hyprland.md) for complete keybindings reference and usage guide.

## Features

- **Modern Wayland Compositor**: Hyprland with GPU acceleration and animations
- **Advanced Window Management**: Dwindle layout with pseudo-tiling and split preservation
- **Animations**: Smooth window, border, and workspace animations
- **Custom Keybindings**: Modal system with Colemak Mod-DH navigation (m, n, e, i)
- **Status Bar**: Waybar integration
- **Notifications**: Mako notification daemon
- **Screen Lock**: Swaylock with effects
- **Idle Management**: Swayidle for automatic screen locking
- **Wallpaper Management**: Wallpaperd integration
- **Display Management**: Multi-monitor support with automatic detection
- **Lid Switch Handling**: Automatic display management on laptop lid close/open

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Hyprland window manager |
| `waybar.enable` | bool | `true` | Enable Waybar status bar |

## Sub-modules

- **windowrules.nix**: Window-specific rules and behaviors
- **waybar.nix**: Status bar configuration
- **wallpaperd.nix**: Wallpaper management
- **screenshots.nix**: Screenshot utilities (shared with Sway)
- **swayidle.nix**: Idle and sleep management (shared with Sway)

## Usage

Enable Hyprland in your Home Manager configuration:

```nix
{
  dotfiles.gui.hyprland.enable = true;
}
```

## Keybindings

The Hyprland configuration uses Colemak Mod-DH navigation keys (m, n, e, i for left, down, up, right).

### Core Keybindings

- **Super+T**: Open terminal
- **Super+Q**: Close active window
- **Super+Shift+Q**: Exit Hyprland
- **Super+Shift+F**: Toggle floating
- **Super+F**: Fullscreen
- **Super+P**: Toggle floating and pin window
- **Super+Space**: Application launcher (anyrun)

### Window Navigation

- **Super+M**: Focus left
- **Super+N**: Focus down
- **Super+E**: Focus up
- **Super+I**: Focus right

### Window Movement

- **Super+Shift+M**: Swap window left
- **Super+Shift+N**: Swap window down
- **Super+Shift+E**: Swap window up
- **Super+Shift+I**: Swap window right

### Workspaces

- **Super+1-9**: Switch to workspace
- **Super+0**: Switch to workspace 10
- **Super+Shift+1-9**: Move window to workspace
- **Super+Shift+0**: Move window to workspace 10
- **Super+Shift+I**: Next workspace
- **Super+Shift+M**: Previous workspace
- **Mouse Right**: Next workspace
- **Mouse Left**: Previous workspace

### Scratchpad

- **Super+Shift+-**: Move window to scratchpad
- **Super+-**: Toggle scratchpad visibility

### Submaps (Modal Modes)

- **Super+A**: Quick Actions submap (apps, system, tools)
- **Super+R**: Resize mode
- **Super+S**: Scratchpad mode

### Keyboard Layout

- **Super+Shift+Ctrl+Alt+Space**: Toggle between Colemak DH and QWERTY layouts (mega keychord)
- **Super+A, y**: Toggle layout (alternative via quick actions)

### Media Controls

- **XF86AudioRaiseVolume**: Increase volume
- **XF86AudioLowerVolume**: Decrease volume
- **XF86AudioMute**: Toggle mute
- **XF86AudioNext**: Next track
- **XF86AudioPrev**: Previous track
- **XF86AudioStop**: Play/pause
- **XF86MonBrightnessUp**: Increase brightness
- **XF86MonBrightnessDown**: Decrease brightness

### Mouse Controls

- **Super+LMB**: Move window
- **Super+RMB**: Resize window

## Visual Configuration

### Decoration

- **Rounding**: 5px window corners
- **Blur**: Enabled with 3px size and 1 pass
- **Opacity**: Active 100%, inactive 98.25%, fullscreen 100%
- **Dim**: Inactive windows dimmed at 25% strength
- **Border**: 1px with gradient (cyan to green)

### Animations

- **Windows**: 7ms with custom bezier curve
- **Borders**: 10ms default
- **Fade**: 7ms default
- **Workspaces**: 6ms default

### Layout

- **Default**: Dwindle (i3-like tiling)
- **Pseudo-tiling**: Enabled
- **Split Preservation**: Enabled

## Input Configuration

- **Keyboard Layout**: US Colemak DH (primary) and US QWERTY (secondary)
- **Mouse**: Natural scrolling enabled, sensitivity 0.0
- **Touchpad**: Natural scrolling, 0.5x scroll factor, middle button emulation, clickfinger behavior
- **Numlock**: Enabled by default

## Included Packages

- imv, libnotify, mpv, pavucontrol, playerctl
- pulseaudio, swaylock-effects, wl-clipboard, anyrun

## Services

- **Mako**: Notification daemon (top-center anchor, 2750ms timeout)
- **Blueman Applet**: Bluetooth management
- **Gammastep**: Color temperature adjustment (Nashville coordinates)
- **Wallpaperd**: Wallpaper management with Hyprland integration
- **Swayidle**: Idle management

## Device Configuration

The module includes configuration for:
- **at-translated-set-2-keyboard**: Built-in laptop keyboard with Colemak DH
- **dygma-defy-keyboard**: External Dygma Defy keyboard with QWERTY

## Lid Switch Handling

Automatic display management when laptop lid is closed/opened:
- When lid is open: Enable built-in display
- When lid is closed: Disable built-in display (if external monitors present)

## Customization

To customize window rules, edit `windowrules.nix`. To modify keybindings, edit the `bind` section in `default.nix`. For display configuration, modify the `monitor` setting.
