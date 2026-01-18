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
- `devShells.default` - Development environment
- `checks.*` - Pre-commit hooks and linting

### Base Library Flake (`base-lib/flake.nix`)

**Purpose**: Provides shared library functions, utilities, and dependencies for all other flakes.

**Inputs**:
- `nixpkgs` - NixOS package collection
- `home-manager` - Home-manager framework
- `darwin` - nix-darwin framework
- `deploy-rs` - Deployment tool
- `agenix` - Secrets management
- Other utilities (pre-commit-hooks, mac-app-util, titlecase)

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

## How to Add a New Host

### Step 1: Create Host Directory

```bash
mkdir -p flakes/hosts/HOSTNAME
cd flakes/hosts/HOSTNAME
```

### Step 2: Create `flake.nix`

```nix
{
  description = "HOSTNAME system configuration";

  inputs = {
    base-lib.url = "path:../../base-lib";
    nixos-modules.url = "path:../../nixos-modules";
    hm-modules.url = "path:../../hm-modules";
    
    nixpkgs.follows = "base-lib/nixpkgs";
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
    deploy-rs.follows = "base-lib/deploy-rs";
    agenix.follows = "base-lib/agenix";
    
    # Add host-specific inputs here if needed
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = inputs @ {
    self,
    base-lib,
    nixpkgs,
    home-manager,
    flake-utils,
    deploy-rs,
    ...
  }: let
    inherit (base-lib.lib) mkHost mkDeploy;
  in {
    nixosConfigurations.HOSTNAME = mkHost "x86_64-linux" ./configuration.nix;
    
    deploy.nodes.HOSTNAME = mkDeploy self.nixosConfigurations.HOSTNAME;
  };
}
```

### Step 3: Create `configuration.nix`

```nix
{ config, pkgs, inputs, ... }:

{
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix
    
    # Shared modules
    inputs.nixos-modules.nixosModules.common
  ];

  networking.hostName = "HOSTNAME";
  
  # Your configuration here
}
```

### Step 4: Add to Root `flake.nix`

```nix
{
  inputs = {
    # ... existing inputs
    HOSTNAME.url = "path:./flakes/hosts/HOSTNAME";
  };

  outputs = inputs @ {
    # ... existing outputs
    HOSTNAME,
    ...
  }: {
    nixosConfigurations = {
      # ... existing configs
      inherit (HOSTNAME.nixosConfigurations) HOSTNAME;
    };
    
    deploy.nodes = {
      # ... existing nodes
      inherit (HOSTNAME.deploy.nodes) HOSTNAME;
    };
  };
}
```

### Step 5: Test

```bash
# Check the flake
nix flake check

# Build the configuration
nix build .#nixosConfigurations.HOSTNAME.config.system.build.toplevel

# Or use nixos-rebuild
nixos-rebuild build --flake .#HOSTNAME
```

## How to Modify Modules

### Adding a New NixOS Module

1. Create the module in `flakes/nixos-modules/modules/`:

```nix
# flakes/nixos-modules/modules/mymodule/default.nix
{ config, lib, pkgs, ... }:

with lib;

{
  options.dotfiles.mymodule = {
    enable = mkDefaultEnabledOption "My module";
  };

  config = mkIf config.dotfiles.mymodule.enable {
    # Configuration here
  };
}
```

2. Export it from `flakes/nixos-modules/flake.nix`:

```nix
{
  outputs = { ... }: {
    nixosModules.mymodule = import ./modules/mymodule;
  };
}
```

3. Use it in a host configuration:

```nix
{
  imports = [
    inputs.nixos-modules.nixosModules.mymodule
  ];
  
  dotfiles.mymodule.enable = true;
}
```

### Adding a New Home-Manager Module

Follow the same pattern in `flakes/hm-modules/`:

```nix
# flakes/hm-modules/modules/mymodule/default.nix
{ config, lib, pkgs, ... }:

with lib;

{
  options.dotfiles.mymodule = {
    enable = mkDefaultEnabledOption "My module";
  };

  config = mkIf config.dotfiles.mymodule.enable {
    # Configuration here
  };
}
```

### Modifying Shared Code

Changes to `base-lib` are automatically available to all hosts:

1. Edit `flakes/base-lib/lib/default.nix` or related files
2. Run `nix flake update` in the root directory
3. All hosts will use the updated library on next build

## Testing Guidelines

### Test Individual Flakes

```bash
# Test base-lib
nix flake check ./flakes/base-lib

# Test a specific host
nix flake check ./flakes/hosts/HOSTNAME

# Test modules
nix flake check ./flakes/nixos-modules
```

### Test Root Flake

```bash
# Check all outputs
nix flake check

# Show all outputs
nix flake show
```

### Build Configurations

```bash
# Build a NixOS configuration
nix build .#nixosConfigurations.HOSTNAME.config.system.build.toplevel

# Build a Darwin configuration
nix build .#darwinConfigurations.HOSTNAME.system

# Build home-manager configuration
nix build .#nixosConfigurations.HOSTNAME.config.home-manager.users.USERNAME.home.activationPackage
```

### Test Deployment

```bash
# Dry-run deployment
nix run .#deploy -- --dry-activate .#HOSTNAME

# Actual deployment
nix run .#deploy -- .#HOSTNAME
```

### Pre-Commit Checks

```bash
# Run all checks
nix flake check

# Run specific checks
nix run .#checks.x86_64-linux.alejandra
nix run .#checks.x86_64-linux.statix
```

## Common Tasks

### Update All Dependencies

```bash
nix flake update
```

### Update Specific Input

```bash
nix flake update nixpkgs
```

### Lock Specific Version

Edit `flake.nix` and run:

```bash
nix flake lock --update-input INPUT_NAME
```

### View Flake Metadata

```bash
nix flake metadata .
nix flake metadata ./flakes/base-lib
```

### Debug Flake Evaluation

```bash
# Show all outputs
nix flake show

# Show specific output
nix eval .#nixosConfigurations.HOSTNAME --apply 'x: x.config.networking.hostName'
```

## Best Practices

1. **Keep base-lib stable**: Changes to base-lib affect all hosts
2. **Use specialArgs**: Pass data through specialArgs rather than modifying modules
3. **Organize modules**: Group related modules in subdirectories
4. **Document modules**: Add comments explaining module purpose and options
5. **Test before committing**: Run `nix flake check` before pushing changes
6. **Use follows**: Always use `follows` for shared dependencies to ensure consistency
7. **Keep flakes focused**: Each flake should have a single, clear responsibility
8. **Version lock**: Use `flake.lock` to ensure reproducible builds

## Troubleshooting

### Flake Lock Issues

```bash
# Regenerate lock file
nix flake lock --update-input '*'

# Or for specific input
nix flake lock --update-input nixpkgs
```

### Circular Dependencies

Check that inputs don't create cycles:

```bash
nix flake metadata . --json | jq '.locks'
```

### Module Not Found

Ensure the module is:
1. Exported from the flake's `flake.nix`
2. Imported with the correct path
3. The flake is in the inputs

### Build Failures

```bash
# Get more verbose output
nix build .#nixosConfigurations.HOSTNAME -v

# Check configuration
nix eval .#nixosConfigurations.HOSTNAME.config --apply 'x: x.networking.hostName'
```
