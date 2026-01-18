# Archived Darwin Modules

These modules are no longer actively used but are preserved for reference.

## Contents

- **configuration.nix** - Basic Darwin system configuration (nix-daemon, zsh, lorri)
- **desktop.nix** - macOS system defaults (keyboard, trackpad, dock, finder)
- **skhd.nix** - skhd keybindings for yabai window manager

## History

These modules were created for an earlier yabai-based window management setup.
The current suremac configuration uses inline settings in `flakes/hosts/suremac/configuration.nix`
and doesn't use yabai/skhd.

## Restoration

To restore any of these modules:
1. Move the file back to `../modules/`
2. Add the export to `../flake.nix` under `darwinModules`
3. Import in your host configuration
