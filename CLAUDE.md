## Build/Update Commands

- Initial setup: `nixos-rebuild switch --use-remote-sudo --flake .#SYSTEM_NAME`
- Shell aliases for rebuilds:
  - `nixos-switch` - Build and activate a new generation
  - `nixos-build` - Build without activating
  - `nixos-test` - Build and activate temporarily
- Deploy to remote: `nix run .#deploy -- .#hostname` (tom, tootsie, trap, cruber)
- Dev environment: `nix develop`

## Formatting & Linting

- Format code: `alejandra .`
- Lint code: `statix check`
- Pre-commit hooks: Alejandra, Statix, Shellcheck

## Coding Conventions

- **Functions**: Use `mk` prefix (mkHost, mkDeploy, mkCommitCheck)
- **Host configs**: In /hosts directory named after hostname
- **Hardware configs**: In /hosts/hardware-configurations/
- **Module organization**: 
  - NixOS modules in nixpkgs/nixos/
  - Home-manager modules in hm_modules/
- **Options pattern**: 
  - Use `dotfiles.feature.enable = true/false`
  - Helper `mkDefaultEnabledOption` for boolean options

## Style Guidelines

- Use attribute sets with named parameters
- Follow existing patterns for similar functionality
- Statix disabled rules: empty_pattern, repeated_keys

## Keybinding Philosophy

- Use a modal approach with leader keys to organize related commands
- Prefer leader+key over complex chord combinations (e.g., shift+space+t over ctrl+alt+shift+t)
- Key patterns:
  - Leader key `shift+space` activates modal context
  - Second key selects mode category (e.g., t=tab, w=window)
  - Subsequent keys perform specific actions within that mode
  - Modes should auto-exit after actions (except for resize/continuous modes)
  - Use Colemak Mod-DH navigation keys (mnei) instead of arrow keys
  - Reserve arrow keys as alternatives for non-Colemak users
  - Always provide explicit Escape key to exit any mode
  - Keep keyboard shortcuts discoverable and mnemonic (t for tab, w for window)

## WezTerm Configuration Notes

- Module structure:
  - `default.nix` - Home Manager module that ties everything together
  - `init.lua` - Core helper functions (loaded as `wezterm_helpers`)
  - `keys.lua` - Keybinding definitions
  - `appearance.lua` - Visual settings
  - `prototyping.lua.example` - Template for ad-hoc configuration testing
  - `README.md` - Documentation and usage guidance
- Important configurations:
  - Rose Pine Moon color theme
  - Key tables for modal operation (leader, window_management, tab_management, resize_mode, layout_mode)
  - Tab index is zero-based for consistency with other tools
  - Status bar shows currently active key table/mode
  - Unbound keys in leader mode pass through to terminal and exit the mode
  - Window resize mode stays active until explicitly exited
  - Leader key (shift+space) completely replaces current key table to avoid conflicts
- Platform-specific settings are centralized in `helper.apply_platform_settings()`
- Ad-hoc configuration testing with prototyping.lua:
  - Copy prototyping.lua.example to ~/.config/wezterm/prototyping.lua
  - Edit to quickly test experimental settings
  - Settings here override all others
  - Reload with SHIFT+Space, l

## Yazi File Manager Configuration

- Module location: `hm_modules/shell_modules/yazi.nix`
- Launch command: `yy` (shell wrapper that changes directory on exit)
- Key binding philosophy:
  - HJKL keys are unbound in favor of Colemak MNEI navigation
  - Space as leader key for most operations
  - Arrow keys as fallback navigation
  - File operations under Space key (y=copy, d=cut, p=paste, x=trash)
  - Filtering under Space+f (Space+fh to toggle hidden files)
  - Sorting under Space+s (n=natural, s=size, m=time, e=extension)
  - Search with / and ? (like vim)
  - F/F to navigate search results (since n/N used for navigation)
  - Tab operations with simple keys (t=new, C-n/C-e=next/prev, C-w=close)

## Helix-Yazi Integration

- Module location: `hm_modules/helix-yazi-integration`
- Open file picker from Helix with `space.t.f`
- Toggle the picker on/off with the same keybinding
- Yazi stays open when opening files in Helix (unlike native file picker)
- Launch command via Rust with `:pipe-to` to avoid output in Helix
- Environment variable handling:
  - Set env vars on Command object to be inherited by child process
  - Pass `HELIX_PANE_ID` to track original editor pane
  - Set `YAZI_CONFIG_HOME` to use custom config with opener
- Custom Yazi configuration:
  - Inherits all settings from main Yazi config
  - Uses tomlFormat to generate TOML from Nix attrsets
  - Overrides file opener to use integration
  - Prioritizes custom quit binding for proper pane cleanup
- WezTerm pane management:
  - Uses WezTerm CLI for creating/activating/closing panes
  - Directly run command in pane with proper args handling
  - Panes automatically close when Yazi exits
- Handles special characters and spaces in file paths
