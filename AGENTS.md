# Agent Instructions for Dotfiles Repository

## Repository Overview

This is a multi-flake Nix repository managing NixOS and Darwin (macOS) system configurations. The architecture uses independent flakes for each host, with shared module flakes for reusability.

## Repository Structure

```
dotfiles/
├── flake.nix                    # Top-level aggregator flake
├── flakes/
│   ├── base-lib/                # Shared library (mkHost, mkDeploy, SSH keys, overlays)
│   ├── nixos-modules/           # Shared NixOS modules
│   ├── hm-modules/              # Shared home-manager modules  
│   ├── darwin-modules/          # Shared Darwin modules
│   └── hosts/                   # Individual host flakes
│       ├── suremac/             # Darwin (macOS) host
│       ├── trap/                # NixOS host
│       ├── thorny/              # NixOS host
│       ├── tom/                 # NixOS host (home-assistant)
│       ├── cruber/              # NixOS host
│       ├── taz/                 # NixOS host (inactive)
│       └── tootsie/             # NixOS host (inactive)
├── hm_modules/                  # Legacy (modules now in flakes/hm-modules/)
├── secrets/                     # Encrypted secrets (agenix)
└── scripts/                     # Utility scripts
```

## Build/Lint/Test Commands

```bash
# Run all configured lints (alejandra, statix, shellcheck)
jj lint

# Format
alejandra .

# Lint
statix check

# Test (top-level)
nix flake check

# Test (individual host)
nix flake check ./flakes/hosts/<hostname>

# Build NixOS host
nixos-rebuild build --flake .#<hostname>
nixos-rebuild build --flake ./flakes/hosts/<hostname>#<hostname>

# Build Darwin host
darwin-rebuild build --flake .#suremac
darwin-rebuild build --flake ./flakes/hosts/suremac#suremac

# Deploy NixOS hosts (via deploy-rs)
nix run .#deploy -- .#<hostname>

# Deploy Darwin host (manual - deploy-rs doesn't support Darwin)
darwin-rebuild switch --flake .#suremac
```

## Code Style Guidelines

- Format with Alejandra (Nix formatter)
- Lint with Statix (disabled rules: empty_pattern, repeated_keys)
- Use attribute sets with named parameters
- Follow existing patterns for similar functionality
- Use `mk` prefix for library functions (mkHost, mkDeploy)
- Use `dotfiles.feature.enable = true/false` pattern for options
- Helper `mkDefaultEnabledOption` for boolean options
- Configure `permittedInsecurePackages` in individual host flakes (e.g., tom needs openssl-1.1.1w)

## Pre-Push Lints

The `jj push` alias automatically runs lints before pushing. Lints are configured per-repo in `.jj/repo/config.toml`:

```toml
[dotfiles]
push-lints = ["alejandra --check .", "statix check", "fd -e sh -e bash -e zsh -x shellcheck"]
```

- `jj lint` - run lints without pushing
- `jj push` - run lints, then push if they pass
- `jj git push` - push directly, skip lints

## Naming Conventions

- **Host flakes**: `flakes/hosts/<hostname>/` - one directory per host
- **Host configs**: `flakes/hosts/<hostname>/configuration.nix`
- **Hardware configs**: `flakes/hosts/<hostname>/hardware.nix`
- **NixOS modules**: `flakes/nixos-modules/modules/`
- **Home-manager modules**: `flakes/hm-modules/modules/` and `hm_modules/`
- **Darwin modules**: `flakes/darwin-modules/modules/`
- **Library functions**: `flakes/base-lib/lib/`

## Module Placement

| Type | Location | Use for |
|------|----------|---------|
| nixos-modules | `flakes/nixos-modules/modules/` | System services, daemons, NixOS-specific config |
| hm-modules | `flakes/hm-modules/modules/` | User dotfiles, CLI tools, per-user GUI apps |
| darwin-modules | `flakes/darwin-modules/modules/` | macOS-specific (skhd, karabiner, Homebrew) |

## Adding a New Host

1. Create directory: `flakes/hosts/<hostname>/`
2. Create files: `flake.nix`, `configuration.nix`, `hardware.nix` (NixOS only)
3. Use existing host as template (trap for NixOS, suremac for Darwin)
4. Add inputs: base-lib, nixos-modules (or darwin-modules), hm-modules
5. Update top-level `flake.nix` to import the new host
6. Test with `nix flake check ./flakes/hosts/<hostname>`

## Security Best Practices

- Only permit insecure packages where absolutely necessary
- Scope insecure package permissions to specific host flakes
- Add comments explaining why insecure packages are needed
- Never read files under `secrets/` or files ending with `.age` without explicit permission

## Keybinding Philosophy

- Use leader key (shift+space) to activate modal context
- Second key selects mode category (t=tab, w=window)
- Modes auto-exit after actions (except resize/continuous modes)
- Use Colemak Mod-DH navigation keys (mnei) instead of arrow keys
- Always provide explicit Escape key to exit any mode

## Agent VCS and Git Usage Reminder

- Agents MUST NOT run any git commands unless the user explicitly requests git operations
- The repository is managed with the `jj` VCS (colocated); use `jj` or follow user instructions for VCS actions
- If unsure, ask the user before performing any version-control operations

## Changelog Policy

- **Canonical source**: The `jj describe` message is the changelog entry
- **Format**: Keep entries concise; sparing Markdown allowed (short sentences, optional inline code)
- **Splitting changes**: Break disparate changes into separate commits using `jj split`, `jj squash`
- **Style**: Use type/scope prefix (e.g., `feat(opencode): add changelog policy`)
- **Agent consumption**: The changelog agent reads this policy from `AGENTS.md`

## CI (SourceHut)

Jobs in `.builds/` run in parallel on push. SourceHut limits: **4 concurrent jobs**, **5 min timeout** per job.

| Job | Purpose |
|-----|---------|
| `lint-check.yml` | alejandra, statix, `nix flake check` |
| `build-suremac.yml` | Darwin flake validation (`--no-build` on Linux) |
| `build-tom.yml` | Build tom NixOS config |
| `build-trap.yml` | Build trap NixOS config |
| `build-thorny.yml` | Build thorny NixOS config |
| `build-cruber.yml` | Build cruber NixOS config |

**Note**: Inactive hosts (taz, tootsie) are intentionally excluded from CI. They remain in the repo for reference but are not actively maintained or deployed. Adding CI for them would consume limited SourceHut job slots without benefit.

**Critical**: Never track `result` symlinks—they point to local store paths and break CI. See `.gitignore` patterns: `/result`, `/result-*`, `flakes/hosts/*/result`.

## Troubleshooting

See `docs/troubleshooting/` for common issues and solutions:

- **Sudo/setuid broken (`nobody:nogroup` ownership)**: If `sudo` fails with permission errors and `/run/wrappers/bin/sudo` is owned by `nobody:nogroup`, see `docs/troubleshooting/sudo-setuid-nobody-nogroup.md`. This typically occurs when NixOS was installed from within a user namespace.

## Host-Specific Notes

| Host | System | Notes |
|------|--------|-------|
| suremac | aarch64-darwin | Use `darwin-rebuild`, not deploy-rs |
| trap | x86_64-linux | COSMIC desktop, System76 |
| thorny | x86_64-linux | COSMIC desktop, System76 Thelio |
| tom | x86_64-linux | Requires openssl-1.1.1w for home-assistant |
| cruber | x86_64-linux | COSMIC desktop, Dell XPS |
| taz | x86_64-linux | Inactive, Linode VM, Searx |
| tootsie | x86_64-linux | Inactive, Linode VM, Tailscale exit node |
