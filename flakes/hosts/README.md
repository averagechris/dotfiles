# Host Configurations

Each host is a self-contained flake that can be built and deployed independently.

## Hosts

| Host | System | Purpose | Status |
|------|--------|---------|--------|
| **suremac** | aarch64-darwin | Personal MacBook | Active |
| **trap** | x86_64-linux | COSMIC desktop, System76 | Active |
| **thorny** | x86_64-linux | COSMIC desktop, System76 Thelio | Active |
| **tom** | x86_64-linux | Home server (home-assistant) | Active |
| **cruber** | x86_64-linux | COSMIC desktop, Dell XPS | Active |
| **taz** | x86_64-linux | Linode VM, Searx | Inactive |
| **tootsie** | x86_64-linux | Linode VM, Tailscale exit node | Inactive |

## Build Commands

```bash
# NixOS
nh os build . --hostname HOSTNAME
nh os switch . --hostname HOSTNAME

# macOS (Darwin)
nh darwin build . --hostname suremac
nh darwin switch . --hostname suremac

# Deploy to remote NixOS host
nix run .#deploy -- .#HOSTNAME
nix run .#deploy -- --dry-activate .#HOSTNAME  # dry-run
```

## Host Structure

```
flakes/hosts/HOSTNAME/
├── flake.nix           # Flake configuration
├── flake.lock          # Locked dependencies
├── configuration.nix   # System configuration
└── hardware.nix        # Hardware config (NixOS only)
```

## Input Duplication Pattern

Each host flake declares nearly identical input blocks. **This is intentional** and supports flake independence:

### Why Inputs Are Duplicated

1. **Standalone builds**: Each host can be built independently without the root flake
   ```bash
   nh os build ./flakes/hosts/trap --hostname trap
   ```

2. **Clear dependencies**: Each host explicitly declares what it needs, making dependencies transparent

3. **Flexible updates**: Individual hosts can be updated independently if needed (though `follows` keeps them synchronized)

### The `follows` Pattern

All host flakes use `follows` to ensure consistent versions across the repository:

```nix
inputs = {
  base-lib.url = "path:../../base-lib";
  nixpkgs.follows = "base-lib/nixpkgs";           # Use base-lib's nixpkgs
  home-manager.follows = "base-lib/home-manager"; # Use base-lib's home-manager
  # ... other follows ...
};
```

This pattern ensures:
- All hosts use the same `nixpkgs` version
- All hosts use the same `home-manager` version
- Dependency versions are controlled from `base-lib/flake.nix`
- No version conflicts between hosts

### Not Technical Debt

The duplication is **not** a limitation to be refactored away. It's an architectural choice that:
- Enables independent host builds
- Makes each host's dependencies explicit
- Allows future flexibility (e.g., one host on a different nixpkgs version if needed)
- Follows Nix flake best practices for modular systems

## Special Notes

- **suremac**: Uses `darwin-rebuild`, not deploy-rs
- **tom**: Requires `openssl-1.1.1w` for home-assistant (permitted in base-lib)

## Creating a New Host

1. Copy an existing host directory as template (trap for NixOS, suremac for Darwin)
2. Update `flake.nix` description and hostname
3. Update `configuration.nix` with host-specific settings
4. Generate `hardware.nix` on target system: `nixos-generate-config --show-hardware-config`
5. Add to root `flake.nix` inputs and outputs
6. Test: `nom flake check ./flakes/hosts/HOSTNAME`
