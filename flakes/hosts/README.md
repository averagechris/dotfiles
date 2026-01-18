# Host Configurations

This directory contains individual flake configurations for each system in the fleet. Each host is a self-contained flake that can be built and deployed independently.

## Host Overview

| Host | Type | System | Purpose | Status |
|------|------|--------|---------|--------|
| **suremac** | macOS | aarch64-darwin | Personal MacBook | Active |
| **trap** | NixOS | x86_64-linux | Remote server | Active |
| **thorny** | NixOS | x86_64-linux | Development machine | Active |
| **tom** | NixOS | x86_64-linux | Home server | Active |
| **cruber** | NixOS | x86_64-linux | Build machine | Active |
| **taz** | NixOS | x86_64-linux | Testing machine | Active |
| **tootsie** | NixOS | x86_64-linux | Utility machine | Active |

## Host Details

### suremac (macOS)

**Type**: Darwin (macOS)  
**System**: aarch64-darwin (Apple Silicon)  
**Purpose**: Personal MacBook for development and daily use

**Build Command**:
```bash
nix run nix-darwin -- switch --flake .#suremac
```

**Deployment**: Not applicable (local system only)

**Special Notes**:
- Uses `darwin-rebuild` instead of `nixos-rebuild`
- Includes mac-app-util for application management
- Home-manager integration for user configuration
- Supports Homebrew packages through nixpkgs

**Key Modules**:
- Darwin system configuration
- Home-manager user setup
- macOS-specific applications

**Configuration Path**: `flakes/hosts/suremac/configuration.nix`

---

### trap (NixOS)

**Type**: NixOS  
**System**: x86_64-linux  
**Purpose**: Remote server for hosting services

**Build Command**:
```bash
nixos-rebuild build --flake .#trap
```

**Deploy Command**:
```bash
nix run .#deploy -- .#trap
```

**Deployment Details**:
- SSH user: `chris`
- Root user: `root`
- Fast connection: enabled
- Magic rollback: disabled
- Auto rollback: disabled

**Special Notes**:
- Deployable via deploy-rs
- Configured for remote SSH access
- Suitable for long-running services

**Configuration Path**: `flakes/hosts/trap/configuration.nix`

---

### thorny (NixOS)

**Type**: NixOS  
**System**: x86_64-linux  
**Purpose**: Development machine for testing and development

**Build Command**:
```bash
nixos-rebuild build --flake .#thorny
```

**Deploy Command**:
```bash
nix run .#deploy -- .#thorny
```

**Deployment Details**:
- SSH user: `chris`
- Root user: `root`
- Fast connection: enabled
- Magic rollback: disabled
- Auto rollback: disabled

**Special Notes**:
- Deployable via deploy-rs
- Development-focused configuration
- Suitable for testing new features

**Configuration Path**: `flakes/hosts/thorny/configuration.nix`

---

### tom (NixOS)

**Type**: NixOS  
**System**: x86_64-linux  
**Purpose**: Home server for local services and storage

**Build Command**:
```bash
nixos-rebuild build --flake .#tom
```

**Deploy Command**:
```bash
nix run .#deploy -- .#tom
```

**Deployment Details**:
- SSH user: `chris`
- Root user: `root`
- Fast connection: enabled
- Magic rollback: disabled
- Auto rollback: disabled

**Special Notes**:
- **IMPORTANT**: Requires `openssl-1.1.1w` for home-assistant compatibility
- This insecure package is automatically permitted in base-lib's `mkHost` function
- Deployable via deploy-rs
- Runs home-assistant and other home automation services

**Special Configuration**:
```nix
# In base-lib/lib/default.nix
permittedInsecurePackages =
  if hostPath == ./hosts/tom.nix
  then ["openssl-1.1.1w"]
  else [];
```

**Configuration Path**: `flakes/hosts/tom/configuration.nix`

---

### cruber (NixOS)

**Type**: NixOS  
**System**: x86_64-linux  
**Purpose**: Build machine for compiling packages and running CI

**Build Command**:
```bash
nixos-rebuild build --flake .#cruber
```

**Deploy Command**:
```bash
nix run .#deploy -- .#cruber
```

**Deployment Details**:
- SSH user: `chris`
- Root user: `root`
- Fast connection: enabled
- Magic rollback: disabled
- Auto rollback: disabled

**Special Notes**:
- Deployable via deploy-rs
- Optimized for build performance
- May use remote builders

**Configuration Path**: `flakes/hosts/cruber/configuration.nix`

---

### taz (NixOS)

**Type**: NixOS  
**System**: x86_64-linux  
**Purpose**: Testing machine for validating configurations

**Build Command**:
```bash
nixos-rebuild build --flake .#taz
```

**Deploy Command**:
```bash
nix run .#deploy -- .#taz
```

**Deployment Details**:
- SSH user: `chris`
- Root user: `root`
- Fast connection: enabled
- Magic rollback: disabled
- Auto rollback: disabled

**Special Notes**:
- Deployable via deploy-rs
- Used for testing new configurations before production
- Isolated testing environment

**Configuration Path**: `flakes/hosts/taz/configuration.nix`

---

### tootsie (NixOS)

**Type**: NixOS  
**System**: x86_64-linux  
**Purpose**: Utility machine for miscellaneous tasks

**Build Command**:
```bash
nixos-rebuild build --flake .#tootsie
```

**Deploy Command**:
```bash
nix run .#deploy -- .#tootsie
```

**Deployment Details**:
- SSH user: `chris`
- Root user: `root`
- Fast connection: enabled
- Magic rollback: disabled
- Auto rollback: disabled

**Special Notes**:
- Deployable via deploy-rs
- General-purpose utility machine
- Flexible configuration for various tasks

**Configuration Path**: `flakes/hosts/tootsie/configuration.nix`

---

## Building Hosts

### Build Locally

To build a configuration without activating it:

```bash
# NixOS
nixos-rebuild build --flake .#HOSTNAME

# macOS (Darwin)
nix build .#darwinConfigurations.HOSTNAME.system
```

### Build and Activate

To build and immediately activate a configuration:

```bash
# NixOS (requires sudo for system changes)
nixos-rebuild switch --use-remote-sudo --flake .#HOSTNAME

# macOS (Darwin)
nix run nix-darwin -- switch --flake .#HOSTNAME
```

### Build Specific Output

To build just the system closure without activating:

```bash
nix build .#nixosConfigurations.HOSTNAME.config.system.build.toplevel
```

### Build Home-Manager Configuration

To build just the home-manager configuration:

```bash
nix build .#nixosConfigurations.HOSTNAME.config.home-manager.users.USERNAME.home.activationPackage
```

## Deploying Hosts

### Prerequisites for Deployment

1. Host must be reachable via SSH
2. SSH key must be configured (typically `~/.ssh/id_ed25519`)
3. User `chris` must have passwordless sudo access
4. NixOS must be installed on the target system

### Deploy to Remote Host

```bash
# Deploy a configuration
nix run .#deploy -- .#HOSTNAME

# Dry-run (show what would be deployed)
nix run .#deploy -- --dry-activate .#HOSTNAME

# Deploy with verbose output
nix run .#deploy -- -v .#HOSTNAME
```

### Deployment Process

1. **Build**: Configuration is built on the local machine
2. **Copy**: Closure is copied to remote host
3. **Activate**: Configuration is activated on remote host
4. **Rollback**: If activation fails, previous configuration is restored

### Troubleshooting Deployment

```bash
# Check SSH connectivity
ssh -v chris@HOSTNAME

# Check if NixOS is installed
ssh chris@HOSTNAME 'nixos-version'

# Check sudo access
ssh chris@HOSTNAME 'sudo -n true'

# View deployment logs
nix run .#deploy -- -v .#HOSTNAME 2>&1 | tee deploy.log
```

## Creating a New Host

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
    
    # Add host-specific inputs if needed
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
    # For NixOS
    nixosConfigurations.HOSTNAME = mkHost "x86_64-linux" ./configuration.nix;
    deploy.nodes.HOSTNAME = mkDeploy self.nixosConfigurations.HOSTNAME;
    
    # For macOS (Darwin)
    # darwinConfigurations.HOSTNAME = mkHost "aarch64-darwin" ./configuration.nix;
  };
}
```

### Step 3: Create `configuration.nix`

For NixOS:

```nix
{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    inputs.nixos-modules.nixosModules.common
  ];

  networking.hostName = "HOSTNAME";
  
  # Your configuration here
  system.stateVersion = "24.05";
}
```

For macOS (Darwin):

```nix
{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.darwin-modules.darwinModules.common
  ];

  networking.hostName = "HOSTNAME";
  
  # Your configuration here
  system.stateVersion = 4;
}
```

### Step 4: Create Hardware Configuration (NixOS only)

```bash
# On the target system, generate hardware configuration
nixos-generate-config --root /mnt

# Copy to your flake
cp /mnt/etc/nixos/hardware-configuration.nix flakes/hosts/HOSTNAME/
```

Or create a minimal one:

```nix
# flakes/hosts/HOSTNAME/hardware-configuration.nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };
}
```

### Step 5: Add to Root `flake.nix`

Edit `/Users/chris/dotfiles/flake.nix`:

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

### Step 6: Test

```bash
# Check the flake
nix flake check

# Build the configuration
nix build .#nixosConfigurations.HOSTNAME.config.system.build.toplevel

# Or use nixos-rebuild
nixos-rebuild build --flake .#HOSTNAME
```

### Step 7: Deploy (if remote)

```bash
# Dry-run
nix run .#deploy -- --dry-activate .#HOSTNAME

# Actual deployment
nix run .#deploy -- .#HOSTNAME
```

## Host Structure

Each host directory contains:

```
flakes/hosts/HOSTNAME/
├── flake.nix                    # Flake configuration
├── configuration.nix            # System configuration
├── hardware-configuration.nix   # Hardware-specific config (NixOS only)
└── flake.lock                   # Locked dependencies
```

## Common Host Configuration Patterns

### Enable a Module

```nix
{
  imports = [
    inputs.nixos-modules.nixosModules.mymodule
  ];
  
  dotfiles.mymodule.enable = true;
}
```

### Configure Home-Manager

```nix
{
  home-manager.users.chris = { config, lib, pkgs, ... }: {
    imports = [
      inputs.hm-modules.homeManagerModules.mymodule
    ];
    
    dotfiles.mymodule.enable = true;
  };
}
```

### Add System Packages

```nix
{
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
  ];
}
```

### Configure Services

```nix
{
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
}
```

### Use SSH Keys

```nix
{ sshKeys, ... }:

{
  users.users.root.openssh.authorizedKeys.keys = [
    sshKeys.chris.thelio
  ];
}
```

## Troubleshooting

### Build Fails

```bash
# Get verbose output
nix build .#nixosConfigurations.HOSTNAME.config.system.build.toplevel -v

# Check configuration
nix eval .#nixosConfigurations.HOSTNAME.config.networking.hostName
```

### Deployment Fails

```bash
# Check SSH connectivity
ssh -v chris@HOSTNAME

# Check remote NixOS
ssh chris@HOSTNAME 'nixos-version'

# Check sudo access
ssh chris@HOSTNAME 'sudo -n true'

# View deployment logs
nix run .#deploy -- -v .#HOSTNAME 2>&1 | tee deploy.log
```

### Module Not Found

```bash
# Check module exports
nix flake show ./flakes/nixos-modules

# Verify import path
nix eval ./flakes/nixos-modules#nixosModules.mymodule
```

### Flake Lock Issues

```bash
# Update lock file
nix flake lock --update-input '*'

# Or specific input
nix flake lock --update-input nixpkgs
```

## Best Practices

1. **Keep configurations DRY**: Use shared modules for common settings
2. **Document special requirements**: Add comments for non-obvious configurations
3. **Test before deploying**: Use `--dry-activate` for remote deployments
4. **Version lock**: Commit `flake.lock` to version control
5. **Use specialArgs**: Pass data through specialArgs rather than hardcoding
6. **Organize modules**: Group related settings in separate files
7. **Handle secrets**: Use agenix for sensitive data
8. **Monitor deployments**: Check logs after deployment

## Quick Reference

### Build Commands

```bash
# Build locally
nixos-rebuild build --flake .#HOSTNAME

# Build and activate
nixos-rebuild switch --use-remote-sudo --flake .#HOSTNAME

# Build specific output
nix build .#nixosConfigurations.HOSTNAME.config.system.build.toplevel
```

### Deployment Commands

```bash
# Deploy
nix run .#deploy -- .#HOSTNAME

# Dry-run
nix run .#deploy -- --dry-activate .#HOSTNAME

# Verbose
nix run .#deploy -- -v .#HOSTNAME
```

### Debugging Commands

```bash
# Show configuration
nix eval .#nixosConfigurations.HOSTNAME.config

# Show specific option
nix eval .#nixosConfigurations.HOSTNAME.config.networking.hostName

# Show flake outputs
nix flake show

# Check flake
nix flake check
```
