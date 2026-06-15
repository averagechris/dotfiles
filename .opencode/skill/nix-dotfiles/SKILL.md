---
name: nix-dotfiles
description: |
  Multi-flake Nix dotfiles repository reference. Use when working with NixOS/Darwin configurations,
  home-manager modules, host flakes, or the base-lib. Covers repo structure, build commands,
  code style, and patterns specific to this dotfiles architecture.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: nix
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
# Format all Nix files quietly (use -qq to suppress error details too)
alejandra -q .

# Lint
statix check

# Test top-level flake
nix flake check

# Test individual host flake
nix flake check ./flakes/hosts/<hostname>

# Routine flake and manifest-enrolled manual package updates
update-flakes --check
update-flakes

# Build NixOS host (preferred ergonomic wrapper)
nh os build . --hostname <hostname>
nh os build ./flakes/hosts/<hostname> --hostname <hostname>

# Build Darwin host (preferred ergonomic wrapper)
nh darwin build . --hostname suremac
nh darwin build ./flakes/hosts/suremac --hostname suremac

# Deploy NixOS hosts (via deploy-rs)
nix run .#deploy -- .#<hostname>

# Quiet deploy wrapper; runs host checks, then buffers deploy output
nix run .#deploy-quiet -- <hostname>

# Deploy Darwin host (manual - deploy-rs doesn't support Darwin)
nh darwin switch . --hostname suremac
```

Prefer `nh` for NixOS/Darwin build, test, and switch workflows. Use `nom` for raw
Nix build/develop commands (`nom build`, `nom develop`) so output is easier
to scan, but use `nix flake check` for flake checks because this `nom` wrapper
does not support `nom flake check`. In noninteractive agent/tool contexts, add `--no-nom` to `nh` builds or
switches (for example, `nh os build -q --no-nom . --hostname tater`) to avoid the
clock/progress animation and most store-path chatter flooding captured logs. Fall back to `nix`,
`nixos-rebuild`, or `darwin-rebuild` only when `nh`/`nom` cannot express the
operation or when a user explicitly asks for the lower-level command.

Use `update-flakes` from the dev shell (or `nix run .#update-flakes -- ...`) for
routine dependency updates. It updates flake locks plus enabled fixed-hash packages from
`manual-package-updates.json`; use `--no-manual-packages` for flake-only
runs, `--manual-packages-only` for fixed-hash packages only,
`--manual-package NAME` to select one package, and `--skip-manual-package NAME`
for one-off unenrollment. Persistently unenroll a manual package by setting
`enabled = false` in the manifest. For GitHub-release manual packages, cooldowns
select the newest non-prerelease release old enough for the cooldown window. Raw
`nix flake update` output is hidden by default; pass `--show-output` only when
debugging.

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
| Type | Location |
|------|----------|
| Host flakes | `flakes/hosts/<hostname>/` |
| Host configs | `flakes/hosts/<hostname>/configuration.nix` |
| Hardware configs | `flakes/hosts/<hostname>/hardware.nix` |
| NixOS modules | `flakes/nixos-modules/modules/` |
| Home-manager modules | `flakes/hm-modules/modules/` and `hm_modules/` |
| Darwin modules | `flakes/darwin-modules/modules/` |
| Library functions | `flakes/base-lib/lib/` |

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
| tater | x86_64-linux | ThinkPad T14s Gen 5 AMD |
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

### Merging Configurations
```nix
config = lib.mkMerge [
  (lib.mkIf condition1 { ... })
  (lib.mkIf condition2 { ... })
];
```

### Force Override
```nix
option = lib.mkForce "value";
```

## Debugging Nix Issues

### Common Commands
```bash
# Show flake outputs
nix flake show

# Evaluate an attribute
nix eval .#<attr>

# Build with trace
nom build .#<attr> --show-trace

# Check flake
nix flake check

# Update a specific input
nix flake update <input-name>

# Update an input declared inside a nested flake from the root aggregator lock
nix flake update <host-or-flake>/<input-name>
```

When bumping a flake input in this repo, update all relevant lockfiles. Host and
module flakes have their own `flake.lock` files, and the root aggregator also
locks nested inputs. If the user will run `nh darwin switch .#suremac` or build
from the repo root, the root `flake.lock` must be updated too (for example,
`nix flake update suremac/granola-cli`), not only
`flakes/hosts/suremac/flake.lock`. Verify the resulting package/configuration
from the same flake path the user will use.

### Common Issues

1. **Missing input**: Check that the input is declared in `flake.nix` and passed to modules
2. **Circular import**: Restructure modules to avoid circular dependencies
3. **Type mismatch**: Use `builtins.typeOf` to debug, ensure options have correct types
4. **Infinite recursion**: Often caused by self-referential definitions; use `lib.mkDefault` or restructure

## VCS Notes

- Repository is managed with `jj` (Jujutsu) VCS, colocated with git
- Use `jj` commands, not `git` commands
- See the `jj-vcs` skill for jj-specific guidance

## Documentation

**IMPORTANT**: Always check and update documentation when making changes.

- **`docs/`** - Contains all project documentation
  - `docs/README.md` - Documentation index with all available guides
  - `docs/<module-name>.md` - Module-specific documentation (e.g., `hyprland.md`, `gpg-signing.md`)
  - `docs/troubleshooting/` - Troubleshooting guides for common issues

- **`AGENTS.md`** - Agent instructions and workflows (read this first for any task)
  - Documents conventions, naming patterns, and build commands
  - Lists troubleshooting guides in the Troubleshooting section

## Changelog Policy

- **Canonical source**: The `jj describe` message is the changelog entry
- **Format**: Keep entries concise; sparing Markdown allowed
- **Splitting changes**: Break disparate changes into separate commits using `jj split`, `jj squash`
- **Style**: Use type/scope prefix (e.g., `feat(opencode): add changelog policy`)
