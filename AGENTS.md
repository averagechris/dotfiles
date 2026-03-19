# Agent Instructions for Dotfiles Repository

> **IMPORTANT**: When working with this repository, load the `nix-dotfiles` skill:
> ```
> /load-skill nix-dotfiles
> ```
> This provides context about repo structure, build commands, and patterns.

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
│       ├── tater/               # NixOS host (ThinkPad T14s)
│       ├── trainwreck/          # NixOS host (Hetzner VPS)
│       ├── taz/                 # NixOS host (inactive)
│       └── tootsie/             # NixOS host (inactive)
├── hm_modules/                  # Legacy (modules now in flakes/hm-modules/)
├── secrets/                     # Encrypted secrets (agenix)
├── scripts/                     # Utility scripts
├── docs/                        # Documentation (see docs/README.md)
└── .opencode/                   # OpenCode skills and config
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

## Documentation

See [docs/README.md](/docs/README.md) for documentation index, including:
- [nixos.md](/docs/nixos.md) - General NixOS configuration notes
- [gpg-signing.md](/docs/gpg-signing.md) - GPG signing setup for git and jj commits with agenix

See `docs/troubleshooting/` for common issues and solutions.

## Code Style Guidelines

- Format with Alejandra (Nix formatter)
- Lint with Statix (disabled rules: empty_pattern, repeated_keys)
- Use attribute sets with named parameters
- Follow existing patterns for similar functionality
- Use `mk` prefix for library functions (mkHost, mkDeploy)
- Use `dotfiles.feature.enable = true/false` pattern for options
- Helper `mkDefaultEnabledOption` for boolean options
- Configure `permittedInsecurePackages` in individual host flakes (e.g., tom needs openssl-1.1.1w)

## Documentation Requirements

**All changes must include documentation updates, and all documentation must be accurate to the current code.**

### When Making Changes

1. **Update relevant documentation** - If you modify a module, update its corresponding doc file
2. **Update the docs index** - Add new documentation to `docs/README.md`
3. **Update `AGENTS.md`** - If adding new conventions, modules, or workflows
4. **Keep docs in sync** - Documentation should always reflect the current state

### Documentation Structure

- Module docs: `docs/<module-name>.md` (e.g., `docs/hyprland.md`)
- Index: `docs/README.md` - must list all docs with brief descriptions
- Troubleshooting: `docs/troubleshooting/<issue>.md`
- Agent instructions: `AGENTS.md` (this file)

### Keybinding/Config Documentation

For modules with keybindings or user-facing configuration:
- List all keybindings in table format
- Document submaps/modal modes with their key sequences
- Include "how to use" examples
- Keep keybinding docs in sync with the actual code

## Pre-Push Lints

The `jj push` alias automatically runs lints before pushing. Lints are configured via `.jj-lint.toml` in the repo root (VCS-tracked):

```toml
# .jj-lint.toml
lints = [
  "alejandra --check .",
  "statix check",
  "fd -e sh -e bash -e zsh -x shellcheck"
]
```

Alternatively, you can configure lints in the local repo config (not VCS-tracked):

```toml
# .jj/repo/config.toml
[dotfiles]
push-lints = ["alejandra --check .", "statix check"]
```

- `jj lint` - run lints without pushing
- `jj push` - run lints, then push if they pass
- `jj ship` - finish and push current work; ships the parent of the working copy so an already-empty `@` (for example after `jj new`) does not get pushed to `main`, refuses empty targets, and requires `--bookmark` instead of silently falling back to integration bookmarks
- `jj sync` - fetch, then rebase onto `develop`/`dev`, else `main`/`master`/`trunk`, else `release*`, with `trunk()` as a fallback
- `jj sync --onto main` - override the inferred sync base explicitly (works with any revset)
- `jj git push` - push directly, skip lints

`jj ship` and `jj sync` are implemented by the embedded `jj-workflow` Rust helper in `flakes/hm-modules/modules/jujutsu/jj-workflow/` because the branch/remote resolution logic outgrew shell aliases.

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

### jj-VCS Skill Sync

**Important**: If you modify any jj configuration in this repository (e.g., `.jj-lint.toml`, `.jj/repo/config.toml`, aliases, or lint commands), you **must** update the `jj-vcs` skill accordingly. The skill is defined in `flakes/hm-modules/modules/opencode/skills.nix` and deployed via home-manager to `~/.config/opencode/skills/jj-vcs/SKILL.md`.

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
- **GPG agent lock / keyboxd timeout**: If jj or git fails with "waiting for lock" errors, see `docs/troubleshooting/gpg-agent-lock.md`. The cleanup service should run automatically on login.
- **MT7925e Wi-Fi instability on tater**: If `tater` randomly loses connectivity and only recovers after a reboot, see `docs/troubleshooting/mt7925e-network-instability.md` for mitigation details, log collection, and non-reboot recovery steps.

## Host-Specific Notes

| Host | System | Notes |
|------|--------|-------|
| suremac | aarch64-darwin | Use `darwin-rebuild`, not deploy-rs |
| trap | x86_64-linux | COSMIC desktop, System76 |
| thorny | x86_64-linux | COSMIC desktop, System76 Thelio |
| tom | x86_64-linux | Requires openssl-1.1.1w for home-assistant |
| cruber | x86_64-linux | COSMIC desktop, Dell XPS |
| trainwreck | aarch64-linux | Hetzner VPS, runs openclaw (Telegram AI assistant) |
| taz | x86_64-linux | Inactive, Linode VM, Searx |
| tootsie | x86_64-linux | Inactive, Linode VM, Tailscale exit node |

## Openclaw (trainwreck)

Openclaw is a Telegram AI assistant running on trainwreck. Configuration is in `flakes/hosts/trainwreck/configuration.nix`.

### Instances

There are two openclaw instances running on trainwreck:

| Instance | Service | Purpose |
|----------|---------|---------|
| `grem` | `openclaw-gateway-grem.service` | Production bot |
| `grem-staging` | `openclaw-gateway-grem-staging.service` | Testing config changes |

**Development workflow**: Always make config changes to `instances.grem-staging` first, deploy, and test with the staging Telegram bot. Once verified working, copy the changes to `instances.grem` and deploy again.

### Service Management

```bash
# Production bot
systemctl --user status openclaw-gateway-grem.service
systemctl --user restart openclaw-gateway-grem.service
journalctl --user -u openclaw-gateway-grem.service -f

# Staging bot (use for testing config changes)
systemctl --user status openclaw-gateway-grem-staging.service
systemctl --user restart openclaw-gateway-grem-staging.service
journalctl --user -u openclaw-gateway-grem-staging.service -f
```

**Note**: SSH access from suremac requires the trainwreck public IP (ask the user). Other hosts can use `ssh chris@trainwreck` via Tailscale.

### Directory Structure on trainwreck

| Path | Purpose |
|------|---------|
| `~/.openclaw-grem/` | Grem production state directory |
| `~/.openclaw-grem/openclaw.json` | Config symlink (points to nix store) |
| `~/.openclaw-grem/runtime/openclaw-grem.json` | Runtime config (generated) |
| `~/.openclaw-grem/extensions/` | Symlink to `~/dotfiles/flakes/hosts/trainwreck/clawdbot-extensions/` |
| `~/.openclaw-grem/telegram/` | Telegram session state |
| `~/.openclaw-grem/agents/` | Agent configurations |
| `~/.openclaw-grem/workspace/` | Workspace files
| `/tmp/openclaw/openclaw-gateway.log` | Service log file |

### Personality Documents (Encrypted)

Grem's personality documents are encrypted with agenix (contain personal info):

| Secret | Purpose |
|--------|---------|
| `secrets/trainwreck/grem-AGENTS.md.age` | Agent instructions, security protocol, multi-user awareness |
| `secrets/trainwreck/grem-SOUL.md.age` | Personality, identity, relationship context |
| `secrets/trainwreck/grem-TOOLS.md.age` | Tool documentation and usage guidelines |

**To edit documents:**
```bash
cd ~/dotfiles/secrets
agenix -e trainwreck/grem-AGENTS.md.age  # Opens in $EDITOR
agenix -e trainwreck/grem-SOUL.md.age
agenix -e trainwreck/grem-TOOLS.md.age
```

Documents are decrypted at activation time and symlinked to `~/.openclaw-grem/workspace/`.

### Custom Extensions

Extensions live in `flakes/hosts/trainwreck/clawdbot-extensions/`:

- `kagi-search/` - Kagi search integration
- `meme-generator/` - Meme generation (imgflip + AI)
- `image-generator/` - AI image generation (profile pics, artwork)
- `opencode-delegate/` - Delegate coding tasks to opencode

**Important**: After pushing changes to extensions, you must also pull on trainwreck:

```bash
ssh chris@<trainwreck-ip> "cd ~/dotfiles && git pull"
systemctl --user restart openclaw-gateway-grem.service
```

### Session Isolation

Each DM conversation gets its own isolated session (`session.dmScope = "per-peer"`). This means:

- Your girlfriend has her own session with Grem (separate context/memory)
- Other users each get their own isolated session
- Group chats have their own sessions (separate from DMs)

**Identity Links** allow you to share a session across platforms. Your Telegram ID is linked under `chris`:

```nix
session.identityLinks = {
  chris = ["telegram:7281917558"];
};
```

**To add more platforms** (Discord, Signal, Slack, etc.), add them to the list:

```nix
session.identityLinks = {
  chris = [
    "telegram:7281917558"
    "discord:YOUR_DISCORD_USER_ID"
    "signal:+15551234567"
    "slack:YOUR_SLACK_USER_ID"
  ];
};
```

This way all your DMs across platforms share the same session context.

### Deploying trainwreck

Deploy-rs has issues with cross-architecture builds. Use this approach instead:

```bash
# Push changes first
jj push

# SSH and rebuild on trainwreck directly
ssh chris@<trainwreck-ip> "cd ~/dotfiles && git pull && sudo nixos-rebuild switch --flake .#trainwreck"
```
