# CLAUDE.md for NixOS Dotfiles

## System Structure

- Projects directory: Located at `~/projects/`
  - Contains source code for important projects/dependencies
  - Used for referencing documentation and code when needed
  - Specific project repos:
    - home-manager: `~/projects/home-manager/` - Source for Home Manager
    - wezterm: `~/projects/wezterm/` - Source for WezTerm terminal emulator
    - kitty: `~/projects/kitty/` - Source for Kitty terminal emulator
    - helix: `~/projects/helix/` - Source for Helix editor

## Build/Update Commands

- Initial setup: `nixos-rebuild switch --use-remote-sudo --flake .#SYSTEM_NAME`
- Shell aliases for rebuilds:
  - `nixos-switch` - Build and activate a new generation
  - `nixos-build` - Build without activating
  - `nixos-test` - Build and activate temporarily
- Deploy to remote: `nix run .#deploy -- .#hostname` (tom, tootsie, trap, cruber)
- Dev environment: `nix develop`

## Claude-Kitty Integration

- Location: `nixpkgs/scripts/kitty-claude.py` - Python script
- Configuration: `nixpkgs/shell/shell_extras.nix` - Nix packaging
- Helix keybindings: `nixpkgs/helix.nix` - Under `space.c` namespace

### Helix Keybindings for Claude

- `space.c.e` - Explain selection (save first)
- `space.c.E` - Explain selection (no save)
- `space.c.f` - Send function for explanation
- `space.c.c` - Implement TODOs/refactor (save first)
- `space.c.C` - Implement TODOs/refactor (no save)
- `space.c.t` - Generate tests for function
- `space.c.d` - Add/improve function documentation
- `space.c.x` - Fix errors/diagnostics
- `space.c.u` - Get usage examples
- `space.c.o` - Optimize code

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