# base-lib Flake

Foundation library for the dotfiles repository containing shared functions, utilities, and configurations.

## Exports

### Library Functions (`lib`)

- **`mkHost`**: Creates a NixOS or Darwin system configuration
  - Takes `system` and `hostPath` as arguments
  - Handles both Linux (NixOS) and macOS (nix-darwin) systems
  - Includes home-manager integration
  - Configures overlays and special arguments

- **`mkDeploy`**: Creates a deploy-rs configuration for a host
  - Generates deployment profiles for NixOS systems
  - Configures SSH options and deployment settings

- **`mkDeploy'`**: Creates a deploy-rs configuration with interactive sudo
  - Similar to `mkDeploy` but enables `interactiveSudo` for hosts that need it

- **`mkCommitCheck`**: Creates pre-commit hook checks
  - Runs alejandra (formatter), statix (linter), and shellcheck
  - Returns checks for the specified system

- **`specialArgs`**: Generates special arguments for modules
  - Provides `inputs`, `sshKeys`, `system`, `overlays`, `dotfiles_lib`, and `agenix`
  - Used by both NixOS and home-manager modules

- **`dotfiles_lib`**: Helper library for options
  - `mkDefaultEnabledOption`: Creates a boolean option that defaults to true

### SSH Keys (`sshKeys`)

SSH public keys organized by user and host:

- `chris.thelio`: Chris's key for thelio
- `chris.xps`: Chris's key for xps
- `chris.trap`: Chris's key for trap
- `system.thelio`: System key for thelio
- `system.xps`: System key for xps
- `system.trap`: System key for trap
- `usesRemoteBuilders`: Set of systems that use remote builders

### Overlays (`overlays`)

- **`overlays.default`**: Default overlay function (currently empty, can be extended)

## Usage

Import the base-lib flake in your root flake.nix:

```nix
{
  inputs = {
    base-lib.url = "path:./flakes/base-lib";
    # ... other inputs
  };

  outputs = inputs @ { base-lib, ... }:
    with base-lib.lib; {
      nixosConfigurations.myhost = mkHost "x86_64-linux" ./hosts/myhost.nix;
      # ... other outputs
    };
}
```

## Testing

Run flake checks:

```bash
nix flake check ./flakes/base-lib
```

Show flake outputs:

```bash
nix flake show ./flakes/base-lib
```
