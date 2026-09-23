# Dotfiles Repository

This repository contains NixOS and nix-darwin configurations for all machines in the fleet, organized using a multi-flake architecture for modularity and maintainability.

## Issue Tracking

Repository work is tracked in the
[SourceHut projects tracker](https://todo.sr.ht/~averagechris/projects). This is
an umbrella tracker shared by several repositories; dotfiles tickets carry the
`repo:dotfiles` label. See [docs/srht.md](docs/srht.md#repository-issue-tracker)
for the CLI workflow.

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
│       ├── tater/           # NixOS system, ThinkPad T14s desktop
│       ├── trainwreck/      # NixOS system, aarch64 VPS
│       ├── taz/             # NixOS system (inactive)
│       └── tootsie/         # NixOS system (inactive)
├── secrets/                 # Encrypted secrets (agenix)
└── scripts/                 # Utility scripts
```

See [flakes/README.md](flakes/README.md) for detailed architecture documentation.
See [docs/flake-performance-audit.md](docs/flake-performance-audit.md) for
the 2026-07-09 flake performance audit and follow-up plan.

## Available Hosts

| Host | System | Purpose | Notes |
|------|--------|---------|-------|
| **suremac** | aarch64-darwin | Personal MacBook | Uses `darwin-rebuild` |
| **trap** | x86_64-linux | COSMIC desktop, System76 | SSH deployable |
| **thorny** | x86_64-linux | COSMIC desktop, System76 Thelio | SSH deployable |
| **tom** | x86_64-linux | Home server (home-assistant) | Requires `openssl-1.1.1w` |
| **cruber** | x86_64-linux | COSMIC desktop, Dell XPS | SSH deployable |
| **tater** | x86_64-linux | Hyprland desktop, ThinkPad T14s | SSH deployable |
| **trainwreck** | aarch64-linux | SourceHut/Forgejo VPS | Eval in ordinary CI; native ARM build is manual |
| **taz** | x86_64-linux | Linode VM, Searx | Inactive |
| **tootsie** | x86_64-linux | Linode VM, Tailscale exit node | Inactive |

## Development

This repository uses `jj` (Jujutsu) for version control, colocated with git.

### Setting Up Development Environment

```bash
# Enter development shell with all tools
nix develop
direnv allow  # if using direnv
```

### Building and Testing

```bash
# Format code quietly (use -qq to suppress error details too)
alejandra -q .

# Lint code
statix check

# Fast ordinary lint/eval checks
jj lint

# Shared or host eval-only checks
nix flake check --accept-flake-config --no-build ./flakes/hm-modules
nix flake check --accept-flake-config --no-build ./flakes/hosts/tater

# Build a NixOS host
nh os build . --hostname tater

# Explicit comprehensive fleet validation
nix flake check --accept-flake-config

# Quiet deploy wrapper; runs host checks, then buffers deploy output
nix run .#deploy-quiet -- trainwreck

# Show flake outputs
nix flake show
```

In automation, add `--no-write-lock-file` to Nix eval/check/build commands so
validation cannot mutate lock files. The repository CI tier script already does
this.

### GitHub Actions CI

`.github/workflows/dotfiles-checks.yml` runs three bounded jobs for pull requests
and pushes to `main`:

- `fast`: formatting, Statix, ShellCheck, and shared flake eval-only checks.
- `active-host-evals`: evaluates active NixOS host drvPaths for `trap`,
  `thorny`, `tom`, `cruber`, `tater`, and `trainwreck` sequentially in separate
  Nix processes with no builds, no lock writes, and eval cache disabled. The
  hosted job is eval-only because complete host closures are too heavy for
  routine CI. Inactive `taz` and `tootsie` are excluded.
- `coverage-checks`: evaluates suremac's Darwin system only and builds the
  selected high-signal tater/thorny desktop check derivations on x86_64 Linux.
  It does not try to realize a Darwin closure on Linux.

The workflow has read-only repository permissions and neither uses secrets nor
pushes to a cache. Full-fleet checks, native trainwreck builds, and trap
disk/cache diagnostics remain explicit local operations via
`scripts/ci-check-tiers.sh`; they are not automatic hosted jobs. Thorny remains
the operational full-closure builder/cache warmer.

### Adding a New Host

1. Create a new directory in `flakes/hosts/HOSTNAME/`
2. Create `flake.nix`, `configuration.nix`, and `hardware.nix` (NixOS only)
3. Use existing host as template (trap for NixOS, suremac for Darwin)
4. Add the host to the root `flake.nix` inputs and outputs
5. Test with a target eval-only check first, then a target host build or explicit
   full-fleet validation when the change warrants it.

## Documentation

- [flakes/README.md](flakes/README.md) - Multi-flake architecture overview
- [flakes/base-lib/README.md](flakes/base-lib/README.md) - Library API and utilities
- [docs/flake-performance-audit.md](docs/flake-performance-audit.md) -
  2026-07-09 flake performance audit findings and SourceHut burn-down
- [docs/nixos.md](docs/nixos.md) - NixOS installation guide

## License

See [LICENSE](LICENSE) for details.
