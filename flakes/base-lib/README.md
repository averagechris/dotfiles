# base-lib Flake

Foundation library for the dotfiles repository containing shared functions, utilities, and configurations. This flake provides the core building blocks used by all host configurations.

## Overview

The base-lib flake serves as the central hub for:
- System configuration creation (`mkNixosHost`, `mkDarwinHost`)
- Deployment configuration (`mkDeploy`, `mkDeploy'`)
- SSH key management
- Package overlays
- Pre-commit hooks and checks
- Helper utilities for module options

## Library API

### `mkNixosHost({ system, hostPath, extraInputs?, permittedInsecurePackages? })`

Creates a NixOS system configuration.

**Parameters**:
- `system` (string): System architecture (e.g., `"x86_64-linux"`)
- `hostPath` (path): Path to the host's `configuration.nix`
- `extraInputs` (attribute set, optional): Additional flake inputs to pass to modules
- `permittedInsecurePackages` (list, optional): List of insecure packages to permit (e.g., `["openssl-1.1.1w"]`)

**Returns**: A NixOS system configuration for use in `nixosConfigurations`

**Features**:
- Integrates home-manager with global packages enabled
- Configures special arguments for all modules
- Supports custom overlays via extraInputs
- Handles insecure packages (e.g., openssl-1.1.1w for home-assistant)

**Example**:

```nix
{
  inputs = {
    base-lib.url = "path:../../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
  };

  outputs = inputs @ { base-lib, ... }:
    with base-lib.lib; {
      nixosConfigurations.myhost = mkNixosHost {
        system = "x86_64-linux";
        hostPath = ./configuration.nix;
      };
      
      # With insecure packages
      nixosConfigurations.tom = mkNixosHost {
        system = "x86_64-linux";
        hostPath = ./configuration.nix;
        permittedInsecurePackages = ["openssl-1.1.1w"];
      };
    };
}
```

### `mkDarwinHost({ system?, hostPath, extraInputs? })`

Creates a Darwin (macOS) system configuration.

**Parameters**:
- `system` (string, optional): System architecture (defaults to `"aarch64-darwin"`)
- `hostPath` (path): Path to the host's `configuration.nix`
- `extraInputs` (attribute set, optional): Additional flake inputs to pass to modules

**Returns**: A Darwin system configuration for use in `darwinConfigurations`

**Features**:
- Integrates home-manager with global packages enabled
- Includes mac-app-util module for app management
- Configures special arguments for all modules
- Supports custom overlays via extraInputs

**Example**:

```nix
{
  inputs = {
    base-lib.url = "path:../../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
  };

  outputs = inputs @ { base-lib, ... }:
    with base-lib.lib; {
      darwinConfigurations.mymac = mkDarwinHost {
        hostPath = ./configuration.nix;
      };
    };
}
```

### `mkSpecialArgs({ system, extraInputs? })`

Generates special arguments passed to all NixOS and home-manager modules.

**Parameters**:
- `system` (string): System architecture
- `extraInputs` (attribute set, optional): Additional flake inputs to merge with standard inputs

**Returns**: Attribute set with special arguments

**Provided Arguments**:
- `inputs`: All flake inputs (merged with extraInputs if provided)
- `sshKeys`: SSH public keys (see SSH Keys section)
- `system`: System architecture
- `agenix`: Secrets management module
- `dotfiles_lib`: Helper library for module options

**Example**:

```nix
# In a module
{ config, lib, pkgs, inputs, sshKeys, system, dotfiles_lib, agenix, ... }:

{
  # Access special arguments
  users.users.root.openssh.authorizedKeys.keys = [
    sshKeys.chris.thelio
  ];
}
```

**Note**: `mkNixosHost` and `mkDarwinHost` automatically call `mkSpecialArgs` internally, so you typically don't need to call this directly unless building custom host configurations.

### `mkHost(system, hostPath)` (Legacy)

**Deprecated**: Use `mkNixosHost` or `mkDarwinHost` instead.

Creates a NixOS or Darwin system configuration by automatically detecting the system type.

**Parameters**:
- `system` (string): System architecture (e.g., `"x86_64-linux"`, `"aarch64-darwin"`)
- `hostPath` (path): Path to the host's `configuration.nix`

**Returns**: A system configuration that can be used in `nixosConfigurations` or `darwinConfigurations`

**Note**: This function is kept for backwards compatibility but should not be used in new code. Use `mkNixosHost` for NixOS hosts and `mkDarwinHost` for Darwin hosts instead.

### `mkDeploy(host)`

Creates a deploy-rs configuration for deploying to a NixOS system.

**Parameters**:
- `host`: A NixOS system configuration (from `mkHost`)

**Returns**: A deploy-rs node configuration

**Features**:
- Configures SSH deployment
- Sets up automatic rollback
- Enables fast connection mode
- Uses `chris` as SSH user and `root` as deployment user

**Example**:

```nix
{
  outputs = inputs @ { base-lib, ... }:
    with base-lib.lib; {
      nixosConfigurations.myhost = mkHost "x86_64-linux" ./configuration.nix;
      
      deploy.nodes.myhost = mkDeploy self.nixosConfigurations.myhost;
    };
}
```

**Deployment Options**:
- `sshOpts = ["-t"]`: Allocate pseudo-terminal
- `fastConnection = true`: Assume fast connection
- `magicRollback = false`: Don't use magic rollback
- `autoRollback = false`: Manual rollback only

### `mkDeploy'(host)`

Creates a deploy-rs configuration with interactive sudo enabled.

**Parameters**:
- `host`: A NixOS system configuration

**Returns**: A deploy-rs node configuration with `interactiveSudo = true`

**Use Case**: For hosts that require interactive password entry during deployment

**Example**:

```nix
deploy.nodes.myhost = mkDeploy' self.nixosConfigurations.myhost;
```

### `mkCommitCheck(system)`

Creates pre-commit hook checks for code quality.

**Parameters**:
- `system` (string): System architecture (e.g., `"x86_64-linux"`)

**Returns**: Checks attribute set for the specified system

**Checks Included**:
- **alejandra**: Nix code formatter
- **statix**: Nix linter (with empty_pattern and repeated_keys disabled)
- **shellcheck**: Shell script linter

**Example**:

```nix
{
  outputs = inputs @ { base-lib, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: {
      checks = base-lib.lib.mkCommitCheck system;
    });
}
```



### `dotfiles_lib`

Helper library for creating module options.

#### `mkDefaultEnabledOption(description)`

Creates a boolean option that defaults to `true`.

**Parameters**:
- `description` (string): Description of the option

**Returns**: An option definition

**Example**:

```nix
{
  options.dotfiles.mymodule = {
    enable = dotfiles_lib.options.mkDefaultEnabledOption "Enable my module";
  };
}
```

This creates an option that:
- Defaults to `true`
- Can be set to `false` to disable the module
- Has proper documentation

## SSH Keys Structure

SSH public keys are organized in `ssh-keys/default.nix` by user and host.

### Key Format

```nix
{
  chris.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGaGrbXoVGe5fXpOhG6+pUZw+aYANuiDPvoI82jftpPd chris@thesogu.com";
  chris.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPflVyCskMX25z8S3pQLyGbo67zBQyC+eMbCkksRw4o/ chris@thesogu.com";
  system.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos";
  usesRemoteBuilders = {
    inherit (system) thelio xps;
  };
}
```

### Naming Convention

- `chris.HOSTNAME`: Chris's personal key for HOSTNAME
- `system.HOSTNAME`: System key for HOSTNAME
- `usesRemoteBuilders`: Set of systems that use remote builders

### Using SSH Keys

```nix
{ config, sshKeys, ... }:

{
  # Add SSH key to user
  users.users.chris.openssh.authorizedKeys.keys = [
    sshKeys.chris.thelio
  ];

  # Add system key
  users.users.root.openssh.authorizedKeys.keys = [
    sshKeys.system.thelio
  ];

  # Check if system uses remote builders
  nix.distributedBuilds = sshKeys.usesRemoteBuilders.${config.networking.hostName} or false;
}
```

## Overlays

Package overlays for extending nixpkgs with custom packages or modifications.

### `overlays.default`

The default overlay function that can be extended with custom packages.

**Current Exports**:
- `titlecase`: Custom package from sourcehut

**Example Usage**:

```nix
{ config, overlays, ... }:

{
  environment.systemPackages = [
    overlays.titlecase  # From overlay
  ];
}
```

### Adding Custom Overlays

Edit `overlays/default.nix` to add new packages:

```nix
{
  overlays.default = system: final: prev: {
    mypackage = prev.callPackage ./mypackage.nix {};
    titlecase = inputs.titlecase.packages.${system}.default;
  };
}
```

## Inputs

The base-lib flake depends on several external inputs:

| Input | Source | Purpose |
|-------|--------|---------|
| `nixpkgs` | github:NixOS/nixpkgs/nixos-unstable | Package collection |
| `home-manager` | github:nix-community/home-manager/master | User configuration |
| `darwin` | github:nix-darwin/nix-darwin/master | macOS configuration |
| `deploy-rs` | github:serokell/deploy-rs | Remote deployment |
| `pre-commit-hooks` | github:cachix/pre-commit-hooks.nix | Git hooks |
| `agenix` | github:ryantm/agenix | Secrets management |
| `mac-app-util` | github:hraban/mac-app-util | macOS app management |
| `titlecase` | sourcehut:~averagechris/titlecase | Text utility |
| `flake-utils` | github:numtide/flake-utils | Flake utilities |

## Usage Examples

### Basic NixOS Host Configuration

```nix
# flakes/hosts/myhost/flake.nix
{
  inputs = {
    base-lib.url = "path:../../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
    home-manager.follows = "base-lib/home-manager";
  };

  outputs = inputs @ { base-lib, ... }:
    with base-lib.lib; {
      nixosConfigurations.myhost = mkNixosHost {
        system = "x86_64-linux";
        hostPath = ./configuration.nix;
      };
      deploy.nodes.myhost = mkDeploy self.nixosConfigurations.myhost;
    };
}
```

### Basic Darwin Host Configuration

```nix
# flakes/hosts/mymac/flake.nix
{
  inputs = {
    base-lib.url = "path:../../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
    home-manager.follows = "base-lib/home-manager";
  };

  outputs = inputs @ { base-lib, ... }:
    with base-lib.lib; {
      darwinConfigurations.mymac = mkDarwinHost {
        hostPath = ./configuration.nix;
      };
    };
}
```

### Using Special Arguments in Modules

```nix
# configuration.nix
{ config, lib, pkgs, inputs, sshKeys, system, overlays, dotfiles_lib, agenix, ... }:

with lib;

{
  options.dotfiles.mymodule = {
    enable = dotfiles_lib.options.mkDefaultEnabledOption "My module";
  };

  config = mkIf config.dotfiles.mymodule.enable {
    # Use special arguments
    users.users.root.openssh.authorizedKeys.keys = [
      sshKeys.chris.thelio
    ];

    environment.systemPackages = [
      overlays.titlecase
    ];
  };
}
```

### Creating a Shared Module

```nix
# flakes/nixos-modules/modules/mymodule/default.nix
{ config, lib, pkgs, dotfiles_lib, ... }:

with lib;

{
  options.dotfiles.mymodule = {
    enable = dotfiles_lib.options.mkDefaultEnabledOption "My module";
    setting = mkOption {
      type = types.str;
      default = "value";
      description = "A setting";
    };
  };

  config = mkIf config.dotfiles.mymodule.enable {
    # Configuration
  };
}
```

## Testing

### Run Flake Checks

```bash
# Check base-lib itself
nix flake check ./flakes/base-lib

# Check all flakes
nix flake check
```

### Show Flake Outputs

```bash
# Show base-lib exports
nix flake show ./flakes/base-lib

# Show all outputs
nix flake show
```

### Evaluate Library Functions

```bash
# Check mkHost function
nix eval ./flakes/base-lib#lib.mkHost

# Check SSH keys
nix eval ./flakes/base-lib#sshKeys
```

### Build a Configuration

```bash
# Build using mkHost
nix build .#nixosConfigurations.myhost.config.system.build.toplevel

# Build home-manager
nix build .#nixosConfigurations.myhost.config.home-manager.users.USERNAME.home.activationPackage
```

## Troubleshooting

### Module Not Found

Ensure the module is properly exported from the flake:

```bash
nix eval ./flakes/base-lib#lib.mkHost
```

### Special Arguments Not Available

Check that the module is using the correct specialArgs:

```nix
# Correct - receives specialArgs
{ config, lib, pkgs, inputs, sshKeys, ... }:

# Incorrect - missing specialArgs
{ config, lib, pkgs, ... }:
```

### SSH Keys Not Accessible

Verify SSH keys are exported from base-lib:

```bash
nix eval ./flakes/base-lib#sshKeys
```

### Overlay Not Applied

Check that overlays are properly configured in mkHost and used in modules:

```bash
nix eval .#nixosConfigurations.myhost.config.environment.systemPackages
```

## Best Practices

1. **Keep base-lib stable**: Changes affect all hosts
2. **Use specialArgs**: Pass data through specialArgs rather than modifying modules
3. **Document functions**: Add comments explaining function purpose and parameters
4. **Test changes**: Run `nix flake check` before committing
5. **Version lock**: Use `flake.lock` for reproducibility
6. **Use follows**: Always use `follows` for shared dependencies
7. **Organize code**: Group related functions in separate files
8. **Handle edge cases**: Consider different systems (NixOS, Darwin) in functions
