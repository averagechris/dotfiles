# Dotfiles Repository

This repository contains NixOS and nix-darwin configurations for all machines in the fleet, organized using a multi-flake architecture for modularity and maintainability.

## Quick Start

### Prerequisites

- [Nix](https://nixos.org/download.html) installed (with flakes enabled)
- For NixOS: Fresh NixOS installation or existing system
- For macOS: Existing macOS system with Nix

### Building a Host

To build and activate a configuration on the current system:

```bash
# NixOS systems
nixos-rebuild switch --use-remote-sudo --flake .#HOSTNAME

# macOS systems (Darwin)
nix run nix-darwin -- switch --flake .#HOSTNAME
```

For subsequent builds, you can omit the `--flake .#HOSTNAME` argument since the configuration will set the system's hostname for you.

### Deploying to Remote Hosts

To deploy a configuration to a remote NixOS system:

```bash
nix run .#deploy -- .#HOSTNAME
```

This uses `deploy-rs` to remotely build and activate the configuration.

## Repository Structure

This repository uses a **multi-flake architecture** where each host is a separate flake that depends on shared library flakes:

```
dotfiles/
├── flake.nix                 # Root aggregator flake
├── flakes/
│   ├── base-lib/            # Shared library functions and utilities
│   ├── nixos-modules/       # Shared NixOS modules
│   ├── hm-modules/          # Shared home-manager modules
│   ├── darwin-modules/      # Shared nix-darwin modules
│   └── hosts/               # Individual host configurations
│       ├── suremac/         # macOS system
│       ├── trap/            # NixOS system
│       ├── thorny/          # NixOS system
│       ├── tom/             # NixOS system
│       ├── cruber/          # NixOS system
│       ├── taz/             # NixOS system (inactive)
│       └── tootsie/         # NixOS system (inactive)
├── secrets/                 # Encrypted secrets (agenix)
└── scripts/                 # Utility scripts
```

See [flakes/README.md](flakes/README.md) for detailed architecture documentation.

## Available Hosts

| Host | System | Purpose | Notes |
|------|--------|---------|-------|
| **suremac** | aarch64-darwin | Personal MacBook | Uses `darwin-rebuild` |
| **trap** | x86_64-linux | COSMIC desktop, System76 | SSH deployable |
| **thorny** | x86_64-linux | COSMIC desktop, System76 Thelio | SSH deployable |
| **tom** | x86_64-linux | Home server (home-assistant) | Requires `openssl-1.1.1w` |
| **cruber** | x86_64-linux | COSMIC desktop, Dell XPS | SSH deployable |
| **taz** | x86_64-linux | Linode VM, Searx | Inactive |
| **tootsie** | x86_64-linux | Linode VM, Tailscale exit node | Inactive |

## Development

This repository uses `jj` (Jujutsu) for version control, colocated with git.

### Setting Up Development Environment

```bash
# Enter development shell with all tools
nix flake update
direnv allow  # if using direnv
```

### Building and Testing

```bash
# Format code
alejandra .

# Lint code
statix check

# Run all checks
nix flake check

# Show flake outputs
nix flake show
```

### Adding a New Host

1. Create a new directory in `flakes/hosts/HOSTNAME/`
2. Create `flake.nix`, `configuration.nix`, and `hardware.nix` (NixOS only)
3. Use existing host as template (trap for NixOS, suremac for Darwin)
4. Add the host to the root `flake.nix` inputs and outputs
5. Test with `nix flake check`

## Documentation

- [flakes/README.md](flakes/README.md) - Multi-flake architecture overview
- [flakes/base-lib/README.md](flakes/base-lib/README.md) - Library API and utilities
- [docs/nixos.md](docs/nixos.md) - NixOS installation guide

## License

See [LICENSE](LICENSE) for details.
