---
name: nix-dotfiles
description: |
  Multi-flake Nix dotfiles repository reference. Use when working with NixOS/Darwin configurations,
  home-manager modules, host flakes, or the base-lib. Covers repo structure, build commands,
  code style, and patterns specific to this dotfiles architecture.
---

# Nix Dotfiles Repository Skill

Use this skill when working with this multi-flake Nix dotfiles repository.

## Repository Architecture

This is a **multi-flake** Nix repository with independent flakes for each host and shared module flakes.

```
dotfiles/
├── flake.nix                    # Top-level aggregator flake
├── flakes/
│   ├── base-lib/                # Shared library (mkHost, mkDeploy, SSH keys, overlays)
│   ├── nixos-modules/           # Shared NixOS modules
│   ├── hm-modules/              # Shared home-manager modules
│   ├── darwin-modules/          # Shared Darwin modules
│   └── hosts/                   # Individual host flakes
│       ├── suremac/             # Darwin (macOS) host
│       ├── trap/                # NixOS host
│       ├── thorny/              # NixOS host
│       ├── tom/                 # NixOS host (home-assistant)
│       ├── cruber/              # NixOS host
│       ├── taz/                 # NixOS host (inactive)
│       └── tootsie/             # NixOS host (inactive)
├── hm_modules/                  # Home-manager modules (referenced by flakes)
├── secrets/                     # Encrypted secrets (agenix) - DO NOT READ
└── scripts/                     # Utility scripts
```

## Build/Lint/Test Commands

```bash
# Format all Nix files
alejandra .

# Lint
statix check

# Test top-level flake
nix flake check

# Test individual host flake
nix flake check ./flakes/hosts/<hostname>

# Build NixOS host
nixos-rebuild build --flake .#<hostname>
nixos-rebuild build --flake ./flakes/hosts/<hostname>#<hostname>

# Build Darwin host
darwin-rebuild build --flake .#suremac
darwin-rebuild build --flake ./flakes/hosts/suremac#suremac

# Deploy NixOS hosts (via deploy-rs)
nix run .#deploy -- .#<hostname>

# Deploy Darwin host (manual - deploy-rs doesn't support Darwin)
darwin-rebuild switch --flake .#suremac
```

## Code Style Guidelines

- **Formatter**: Alejandra (Nix formatter)
- **Linter**: Statix (disabled rules: `empty_pattern`, `repeated_keys`)
- Use attribute sets with named parameters
- Follow existing patterns for similar functionality

## Naming Conventions

### Library Functions
Use `mk` prefix: `mkHost`, `mkDeploy`, `mkCommitCheck`, `mkDefaultEnabledOption`

### Options Pattern
```nix
dotfiles.feature.enable = true/false;
```

Use `mkDefaultEnabledOption` helper for boolean options.

### File Locations
- **Host flakes**: `flakes/hosts/<hostname>/`
- **Host configs**: `flakes/hosts/<hostname>/configuration.nix`
- **Hardware configs**: `flakes/hosts/<hostname>/hardware.nix`
- **NixOS modules**: `flakes/nixos-modules/modules/`
- **Home-manager modules**: `flakes/hm-modules/modules/` and `hm_modules/`
- **Darwin modules**: `flakes/darwin-modules/modules/`
- **Library functions**: `flakes/base-lib/lib/`

## Adding a New Host

1. Create directory: `flakes/hosts/<hostname>/`
2. Create files: `flake.nix`, `configuration.nix`, `hardware.nix`
3. Use existing host as template:
   - NixOS: use `trap` as template
   - Darwin: use `suremac` as template
4. Add inputs: `base-lib`, `nixos-modules` (or `darwin-modules`), `hm-modules`
5. Update top-level `flake.nix` to import the new host
6. Test with `nix flake check ./flakes/hosts/<hostname>`

## Host-Specific Notes

| Host | System | Notes |
|------|--------|-------|
| suremac | aarch64-darwin | Use `darwin-rebuild`, not deploy-rs |
| trap | x86_64-linux | COSMIC desktop, System76 |
| thorny | x86_64-linux | COSMIC desktop, System76 Thelio |
| tom | x86_64-linux | Requires `openssl-1.1.1w` for home-assistant |
| cruber | x86_64-linux | COSMIC desktop, Dell XPS |
| taz | x86_64-linux | Inactive, Linode VM, Searx |
| tootsie | x86_64-linux | Inactive, Linode VM, Tailscale exit node |

## Security Best Practices

- **NEVER** read files under `secrets/` or files ending with `.age` without explicit permission
- Only permit insecure packages where absolutely necessary
- Scope insecure package permissions to specific host flakes
- Add comments explaining why insecure packages are needed

## Keybinding Philosophy

When working with keybinding configurations:

- Use leader key (shift+space) to activate modal context
- Second key selects mode category (t=tab, w=window)
- Modes auto-exit after actions (except resize/continuous modes)
- Use **Colemak Mod-DH navigation keys** (`mnei`) instead of arrow keys
- Always provide explicit Escape key to exit any mode

## Common Patterns

### Module Structure
```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.myFeature;
in {
  options.dotfiles.myFeature = {
    enable = lib.mkEnableOption "my feature";
    # other options...
  };

  config = lib.mkIf cfg.enable {
    # implementation...
  };
}
```

### Conditional Configuration
```nix
config = lib.mkIf cfg.enable {
  # ...
};
```

### Default Values
```nix
option = lib.mkDefault "value";
```

## VCS Notes

- Repository is managed with `jj` (Jujutsu) VCS, colocated with git
- Use `jj` commands, not `git` commands
- See the `jj-vcs` skill for jj-specific guidance
