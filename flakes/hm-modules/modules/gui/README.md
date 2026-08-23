# GUI configuration module

This module provides the graphical user interface setup with window managers, terminal emulators, and desktop applications.

## Features

- **Window Managers**: Sway (i3-like Wayland) and Hyprland (modern Wayland compositor)
- **Terminal Emulators**: Kitty, WezTerm, Alacritty, and Ghostty
- **Desktop Applications**: Firefox, Signal, Zoom, KeePassXC, and more
- **Status Bar**: Waybar for both Sway and Hyprland
- **Display Management**: Kanshi for multi-monitor configuration
- **Notifications**: Mako notification daemon
- **Theming**: Integrated theme and wallpaper management
- **Accessibility**: Darktable, write-stylus, and other utilities

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable GUI configuration |
| `terminal.package` | package | `pkgs.kitty` | Terminal emulator package |
| `terminal.args` | list | Kitty defaults | Arguments passed to terminal |
| `terminal.binPath` | string | Computed | Full path to terminal binary |

## Sub-modules

### Window managers

- **sway**: i3-like Wayland compositor with custom keybindings and status bar
- **hyprland**: Modern Wayland compositor with animations and advanced features

### Terminal emulators

- **kitty**: GPU-based terminal (default)
- **wezterm**: Cross-platform terminal with Lua configuration
- **alacritty**: GPU-accelerated terminal
- **ghostty**: Fast terminal emulator

### Desktop applications

- **firefox**: Web browser
- **zoom**: Video conferencing
- **signal**: Encrypted messaging
- **keepassxc**: Password manager
- **darktable**: Photo editor
- **write-stylus**: Stylus note-taking

## Usage

Enable the GUI module in your Home Manager configuration:

```nix
{
  dotfiles.gui = {
    enable = true;
    terminal.package = pkgs.kitty;
  };
}
```

This will enable:
- Sway window manager by default
- Kitty terminal emulator
- Firefox, Signal, Zoom, and KeePassXC
- Waybar status bar
- Kanshi display management
- Mako notifications

## Default behavior

When `dotfiles.gui.enable = true`:
- Sway is enabled by default (`dotfiles.gui.sway.enable = true`)
- All terminal emulators are enabled
- Desktop applications are enabled
- Udiskie (USB device manager) is enabled on Linux
- Meganz GUI is enabled

## Customization

To use a different terminal emulator:

```nix
{
  dotfiles.gui = {
    enable = true;
    terminal.package = pkgs.wezterm;
    terminal.args = ["--single-instance"];
  };
}
```

To enable Hyprland instead of Sway:

```nix
{
  dotfiles.gui.enable = true;
  dotfiles.gui.sway.enable = false;
  dotfiles.gui.hyprland.enable = true;
}
```
