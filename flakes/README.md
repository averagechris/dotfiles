# Multi-Flake Architecture

This directory contains the modular flake-based architecture for the dotfiles repository. Each component is a separate flake with clear dependencies and responsibilities.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Root Flake (flake.nix)                   │
│              Aggregates all host configurations              │
└────────────────────────┬────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
    ┌────────┐      ┌────────┐      ┌────────┐
    │ Hosts  │      │ Modules│      │ base-lib
    │ Flakes │      │ Flakes │      │ Flake
    └────────┘      └────────┘      └────────┘
        │                │                │
        ├─ suremac       ├─ nixos-modules │
        ├─ trap          ├─ hm-modules    ├─ nixpkgs
        ├─ thorny        └─ darwin-modules├─ home-manager
        ├─ tom                           ├─ nix-darwin
        ├─ cruber                        ├─ deploy-rs
        ├─ taz                           ├─ agenix
        └─ tootsie                       └─ ...
```

## Flake Dependency Graph

### Root Flake (`flake.nix`)

**Purpose**: Aggregates all host configurations and re-exports them for building and deployment.

**Inputs**:
- All host flakes (suremac, trap, thorny, tom, cruber, taz, tootsie)
- Module flakes (base-lib, nixos-modules, hm-modules, darwin-modules)
- Shared dependencies (nixpkgs, flake-utils, deploy-rs, pre-commit-hooks)

**Outputs**:
- `nixosConfigurations.*` - All NixOS system configurations
- `darwinConfigurations.*` - All Darwin system configurations
- `deploy.nodes.*` - All deployable nodes
- `apps.deploy` - Deploy-rs application
- `devShells.default` - Lean lint/deploy/update development environment
- `devShells.rust` - Default tools plus Rust package development toolchain
- `devShells.ide` - Rust shell plus Nix/Bash/Rust language servers
- `checks.*` - Pre-commit hooks and linting

### Base Library Flake (`base-lib/flake.nix`)

**Purpose**: Provides shared library functions, utilities, and dependencies for all other flakes.

**Inputs**:
- `nixpkgs` - NixOS package collection
- `home-manager` - Home-manager framework
- `darwin` - nix-darwin framework
- `deploy-rs` - Deployment tool
- `agenix` - Secrets management
- Other utilities (pre-commit-hooks, titlecase)

**Exports**:
- `lib.mkHost` - Function to create system configurations
- `lib.mkDeploy` - Function to create deployment configurations
- `lib.mkDeploy'` - Variant with interactive sudo
- `lib.mkCommitCheck` - Pre-commit hook checks
- `lib.specialArgs` - Special arguments for modules
- `lib.dotfiles_lib` - Helper utilities
- `sshKeys` - SSH public keys for all users and hosts
- `overlays.default` - Package overlays

**Key Files**:
- `lib/default.nix` - Library functions
- `ssh-keys/default.nix` - SSH key definitions
- `overlays/default.nix` - Package overlays

### Module Flakes

#### `nixos-modules/flake.nix`
**Purpose**: Shared NixOS modules used by multiple hosts.

**Exports**: NixOS modules for common functionality

#### `hm-modules/flake.nix`
**Purpose**: Shared home-manager modules for user configuration.

**Exports**: Home-manager modules for common user settings

#### `darwin-modules/flake.nix`
**Purpose**: Shared nix-darwin modules for macOS-specific configuration.

**Exports**: Darwin modules for macOS-specific settings

### Host Flakes (`hosts/*/flake.nix`)

**Purpose**: Individual system configurations for each host.

**Pattern**: Each host flake follows the same structure:

```nix
{
  description = "HOSTNAME system configuration";
  
  inputs = {
    base-lib = { url = "path:../../base-lib"; };
    nixos-modules = { url = "path:../../nixos-modules"; };
    hm-modules = { url = "path:../../hm-modules"; };
    # ... other inputs
  };
  
  outputs = inputs @ { base-lib, ... }:
    with base-lib.lib; {
      nixosConfigurations.HOSTNAME = mkHost "SYSTEM" ./configuration.nix;
      # or
      darwinConfigurations.HOSTNAME = mkHost "aarch64-darwin" ./configuration.nix;
      
      deploy.nodes.HOSTNAME = mkDeploy self.nixosConfigurations.HOSTNAME;
    };
}
```

**Inputs**:
- `base-lib` - Shared library functions
- `nixos-modules` or `darwin-modules` - Shared modules
- `hm-modules` - Home-manager modules
- Host-specific inputs (e.g., nixos-hardware, custom packages)

**Outputs**:
- `nixosConfigurations.HOSTNAME` or `darwinConfigurations.HOSTNAME` - System configuration
- `deploy.nodes.HOSTNAME` - Deployment configuration (NixOS only)

## How Each Flake Relates to Others

### Dependency Flow

```
Host Flakes (suremac, trap, etc.)
    ↓ depends on
base-lib + Module Flakes (nixos-modules, hm-modules, darwin-modules)
    ↓ depends on
External Inputs (nixpkgs, home-manager, nix-darwin, etc.)
```

### Data Flow

1. **Root flake** imports all host flakes
2. Each **host flake** imports `base-lib` and module flakes
3. **base-lib** provides library functions and shared configuration
4. **Module flakes** provide reusable NixOS/home-manager/Darwin modules
5. **Host configurations** use library functions to build system configurations

### Shared Dependencies

All flakes follow the same nixpkgs version through `follows`:

```nix
# In each host flake
nixpkgs.follows = "base-lib/nixpkgs";
home-manager.follows = "base-lib/home-manager";
```

This ensures consistency across all hosts and modules.

## Adding Modules

Create module in appropriate location, export from flake, import in host config:

```nix
# flakes/nixos-modules/modules/mymodule/default.nix (or hm-modules, darwin-modules)
{ config, lib, pkgs, ... }:
with lib;
{
  options.dotfiles.mymodule.enable = mkDefaultEnabledOption "My module";
  config = mkIf config.dotfiles.mymodule.enable {
    # Configuration here
  };
}
```

Export from flake and use in host:

```nix
# In host configuration.nix
imports = [ inputs.nixos-modules.nixosModules.mymodule ];
dotfiles.mymodule.enable = true;
```

## Common Commands

```bash
# Testing
nix flake check                              # all flakes
nix flake check ./flakes/hosts/HOSTNAME      # single host

# Building
nh os build . --hostname HOSTNAME
nh darwin build . --hostname suremac

# Updating
update-flakes --check                        # check updates, respecting cooldowns
update-flakes                                # update all repo flakes, respecting cooldowns
nix flake update nixpkgs                     # manually update a specific input

# Debugging
nix flake show
nix eval .#nixosConfigurations.HOSTNAME.config --apply 'x: x.networking.hostName'
```

## Best Practices

- **Keep base-lib stable** — changes affect all hosts
- **Use `follows`** — ensures consistent dependency versions
- **Test before committing** — run `nix flake check`
- **Use `flake.lock`** — commit for reproducible builds
- **Respect update cooldowns** — use `update-flakes` for routine updates so gated fast-moving agent packages such as `pi` / `pi-coding-agent` are not pulled immediately after upstream changes
