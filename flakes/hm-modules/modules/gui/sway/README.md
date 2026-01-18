# Sway Window Manager Configuration

This module provides a highly configured Sway window manager setup for Wayland, including keybindings, status bar, display management, and system utilities.

## Features

- **Window Management**: i3-like tiling window manager for Wayland
- **Custom Keybindings**: Modal keybinding system with Colemak Mod-DH support
- **Status Bar**: Waybar with system information and controls
- **Display Management**: Kanshi for multi-monitor configuration
- **Notifications**: Mako notification daemon
- **Screen Lock**: Swaylock with effects
- **Idle Management**: Swayidle for automatic screen locking and sleep
- **Screenshots**: Screenshot utilities
- **Audio/Media**: Pavucontrol, playerctl for media control
- **System Utilities**: Blueman applet, Gammastep for color temperature

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Sway window manager |

## Sub-modules

- **keybindings.nix**: Modal keybinding system
- **waybar.nix**: Status bar configuration
- **kanshi.nix**: Display management
- **swayidle.nix**: Idle and sleep management
- **sway.nix**: Core Sway configuration
- **screenshots.nix**: Screenshot utilities

## Usage

Enable Sway in your Home Manager configuration:

```nix
{
  dotfiles.gui.sway.enable = true;
}
```

## Keybindings

The Sway configuration uses a modal keybinding system with Colemak Mod-DH navigation keys (m, n, e, i for left, down, up, right).

### Core Keybindings

- **Super+T**: Open terminal
- **Super+Q**: Close active window
- **Super+Shift+Q**: Exit Sway
- **Super+Shift+F**: Toggle floating
- **Super+F**: Fullscreen
- **Super+Space**: Application launcher (nwg-bar)

### Window Navigation

- **Super+M**: Focus left
- **Super+N**: Focus down
- **Super+E**: Focus up
- **Super+I**: Focus right

### Window Movement

- **Super+Shift+M**: Move window left
- **Super+Shift+N**: Move window down
- **Super+Shift+E**: Move window up
- **Super+Shift+I**: Move window right

### Workspaces

- **Super+1-9**: Switch to workspace
- **Super+Shift+1-9**: Move window to workspace

### Media Controls

- **XF86AudioRaiseVolume**: Increase volume
- **XF86AudioLowerVolume**: Decrease volume
- **XF86AudioMute**: Toggle mute
- **XF86MonBrightnessUp**: Increase brightness
- **XF86MonBrightnessDown**: Decrease brightness

## Included Packages

- wldash, imv, libnotify, mpv, pavucontrol, playerctl
- pulseaudio, ranger, swaylock-effects, wl-clipboard

## Services

- **Mako**: Notification daemon (top-center anchor, 2750ms timeout)
- **Blueman Applet**: Bluetooth management
- **Gammastep**: Color temperature adjustment (Nashville coordinates)
- **Kanshi**: Display configuration
- **Waybar**: Status bar

## Configuration Files

- **nwg-panel/drawer.css**: Panel styling
- **nwg-bar/style.css**: Application menu styling
- **nwg-bar/icons**: Application menu icons
- **swaylock/config**: Screen lock configuration

## Display Management

Kanshi automatically manages monitor configuration. Edit the Kanshi configuration to customize display profiles for different docking scenarios.

## Customization

To customize keybindings, edit `keybindings.nix`. To modify the status bar, edit `waybar.nix`. For display profiles, configure Kanshi in `kanshi.nix`.
