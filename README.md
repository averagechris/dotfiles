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
│       ├── taz/             # NixOS system
│       └── tootsie/         # NixOS system
├── nixpkgs/                 # Custom NixOS modules and overlays
└── hm_modules/              # Legacy home-manager modules
```

See [flakes/README.md](flakes/README.md) for detailed architecture documentation.

## Available Hosts

| Host | Type | Purpose | Notes |
|------|------|---------|-------|
| **suremac** | macOS (Darwin) | Personal MacBook | Uses `darwin-rebuild` |
| **trap** | NixOS | Remote server | SSH deployable |
| **thorny** | NixOS | Development machine | SSH deployable |
| **tom** | NixOS | Home server | Requires `openssl-1.1.1w` |
| **cruber** | NixOS | Build machine | SSH deployable |
| **taz** | NixOS | Testing machine | SSH deployable |
| **tootsie** | NixOS | Utility machine | SSH deployable |

See [flakes/hosts/README.md](flakes/hosts/README.md) for detailed host information.

## Development

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
2. Create `flake.nix` and `configuration.nix` (see [flakes/hosts/README.md](flakes/hosts/README.md))
3. Add the host to the root `flake.nix` inputs and outputs
4. Test with `nix flake check`

See [flakes/README.md](flakes/README.md) for detailed instructions.

## Migration from Old Structure

If you're familiar with the previous single-flake structure, here are the key changes:

### Before (Single Flake)
- All configurations in one `flake.nix`
- Shared code duplicated across hosts
- Difficult to test individual hosts

### After (Multi-Flake)
- Each host is a separate flake with its own `flake.nix`
- Shared code in `base-lib`, `nixos-modules`, `hm-modules`, `darwin-modules`
- Root `flake.nix` aggregates all hosts
- Each host can be tested independently
- Cleaner dependency management

### Key Improvements
- **Modularity**: Each host is self-contained and can be developed independently
- **Reusability**: Shared modules and functions are centralized
- **Maintainability**: Changes to shared code are automatically available to all hosts
- **Testing**: Individual flakes can be checked without building all hosts
- **Scalability**: Easy to add new hosts or modules

## Documentation

- [flakes/README.md](flakes/README.md) - Multi-flake architecture overview
- [flakes/base-lib/README.md](flakes/base-lib/README.md) - Library API and utilities
- [flakes/hosts/README.md](flakes/hosts/README.md) - Host configurations and deployment
- [docs/nixos.md](docs/nixos.md) - NixOS-specific documentation

## License

See [LICENSE](LICENSE) for details.
