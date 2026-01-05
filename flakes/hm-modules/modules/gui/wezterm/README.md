# WezTerm Home Manager Configuration

This directory contains a modular configuration for the [WezTerm](https://wezfurlong.org/wezterm/) terminal emulator
using Home Manager.

## Architecture

The configuration is split into several modules:

- **default.nix**: Main Home Manager module that ties everything together
- **init.lua**: Core helpers and platform-specific code (loaded as `wezterm_helpers`)
- **appearance.lua**: Visual settings including colors, fonts, and tab bar
- **keys.lua**: Modal keybinding system similar to Vim/Helix
- **prototyping.lua.example**: Template for experimenting with configurations

## Key Features

1. **Modal keybinding system**
   - Leader key (SHIFT+Space) followed by context-specific commands
   - Key tables for window management, tab management, layout, and resizing
   - Colemak Mod-DH navigation keys (mnei)

2. **Platform-specific customizations**
   - Centralized platform detection
   - Different settings for macOS, Linux, and Windows
   - Support for tiling window managers on Linux

3. **Prototyping System**
   - Make experimental changes without modifying the main configuration
   - Changes loaded last to override any existing settings
   - Clear logging for debugging

## Usage

### Normal Mode

- **SHIFT+Space**: Enter leader mode
- **SHIFT+Space, w**: Window management
- **SHIFT+Space, t**: Tab management
- **SHIFT+Space, l**: Configuration reload

### Experimental Configuration

1. Copy `prototyping.lua.example` to `~/.config/wezterm/prototyping.lua`
2. Edit the file to add experimental settings
3. Reload WezTerm (SHIFT+Space, l) to apply changes

## Extending the Configuration

When adding new features:

1. Place platform-specific code in `init.lua`'s `apply_platform_settings`
2. Keep appearance settings in `appearance.lua`
3. Add new keybindings in `keys.lua`