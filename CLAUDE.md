# CLAUDE.md for NixOS Dotfiles

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