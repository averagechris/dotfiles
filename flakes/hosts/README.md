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
nixos-rebuild build --flake .#HOSTNAME
nixos-rebuild switch --use-remote-sudo --flake .#HOSTNAME

# macOS (Darwin)
darwin-rebuild build --flake .#suremac
darwin-rebuild switch --flake .#suremac

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

## Special Notes

- **suremac**: Uses `darwin-rebuild`, not deploy-rs
- **tom**: Requires `openssl-1.1.1w` for home-assistant (permitted in base-lib)

## Creating a New Host

1. Copy an existing host directory as template (trap for NixOS, suremac for Darwin)
2. Update `flake.nix` description and hostname
3. Update `configuration.nix` with host-specific settings
4. Generate `hardware.nix` on target system: `nixos-generate-config --show-hardware-config`
5. Add to root `flake.nix` inputs and outputs
6. Test: `nix flake check ./flakes/hosts/HOSTNAME`
