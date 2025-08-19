# Agent Instructions for Dotfiles Repository

## Build/Lint/Test Commands
- Format: `alejandra .`
- Lint: `statix check`
- Test: `nix flake check`
- Build: `nixos-rebuild switch --use-remote-sudo --flake .#SYSTEM_NAME`
- Deploy: `nix run .#deploy -- .#hostname`

## Code Style Guidelines
- Use attribute sets with named parameters
- Follow existing patterns for similar functionality
- Format with Alejandra (Nix formatter)
- Lint with Statix (disabled rules: empty_pattern, repeated_keys)
- Use `mk` prefix for functions (mkHost, mkDeploy, mkCommitCheck)
- Use `dotfiles.feature.enable = true/false` pattern for options
- Helper `mkDefaultEnabledOption` for boolean options
- Configure nixpkgs `permittedInsecurePackages` in the `mkHost` function rather than in modules

## Naming Conventions
- Host configs in /hosts directory named after hostname
- Hardware configs in /hosts/hardware-configurations/
- NixOS modules in nixpkgs/nixos/
- Home-manager modules in hm_modules/

## Security Best Practices
- Only permit insecure packages where absolutely necessary
- Use conditional logic to limit scope of insecure package permissions to specific hosts
- Add comments explaining why insecure packages are needed

## Keybinding Philosophy
- Use leader key (shift+space) to activate modal context
- Second key selects mode category (t=tab, w=window)
- Modes auto-exit after actions (except resize/continuous modes)
- Use Colemak Mod-DH navigation keys (mnei) instead of arrow keys
- Always provide explicit Escape key to exit any mode

## Agent VCS and Git Usage Reminder
- Agents MUST NOT run any git commands unless the user explicitly requests git operations.
- The repository is managed with the `jj` VCS (colocated); use `jj` or follow user instructions for VCS actions.
- If unsure, ask the user before performing any version-control operations.
