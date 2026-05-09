# Trainwreck: Hetzner VPS Host Plan

A new NixOS server host for running clawdbot and serving as a personal build server.

## Current Status

**Last Updated**: 2026-01-27

### Completed ✅
- [x] Created trainwreck host directory structure
- [x] Write flake.nix with required inputs (base-lib, nixos-modules, nix-clawdbot, disko)
- [x] Write hardware.nix for ARM64 Hetzner Cloud VPS
- [x] Write disko.nix for declarative disk partitioning
- [x] Write configuration.nix with base modules
- [x] Add trainwreck to top-level flake.nix
- [x] Updated base-lib with `extraOverlays` parameter for `mkNixosHost`
- [x] Added suremac SSH key to base-lib/ssh-keys
- [x] Provisioned Hetzner VPS (existing server: atmo-1-falk)
- [x] Installed NixOS on VPS via nixos-anywhere
- [x] Server is running NixOS 25.05
- [x] SSH access as chris user working
- [x] Deployed full NixOS configuration
- [x] Joined Tailscale network (100.68.122.74)
- [x] Created Telegram bot via @BotFather
- [x] Got Telegram user ID (7281917558)
- [x] Updated secrets/secrets.nix with real host key
- [x] Created agenix secrets (telegram-bot-token.age, openrouter-api-key.age)
- [x] Secrets decrypting successfully via agenix
- [x] Forked nix-clawdbot to SourceHut with NixOS compatibility fixes
- [x] Updated trainwreck to use forked nix-clawdbot
- [x] Clawdbot gateway running and stable
- [x] Enabled lingering for chris user (service persists after logout)

### In Progress
- [ ] Test Telegram bot (send a message to verify it responds)
- [ ] File upstream PRs for nix-clawdbot fixes

---

## Overview

**Host name**: `trainwreck`  
**Platform**: Hetzner Cloud ARM VPS (aarch64-linux)  
**Server**: cax41 - 16 cores, 32GB RAM, 320GB disk  
**IP Address**: 49.13.143.249  
**Primary purpose**: Run clawdbot personal AI assistant via Telegram  
**Secondary purpose**: Tailscale-accessible Nix remote build server

---

## nix-clawdbot Fork

**Fork location**: https://git.sr.ht/~averagechris/nix-clawdbot

The fork includes these fixes for NixOS compatibility:

1. **Full coreutils paths** - Use `${pkgs.coreutils}/bin/mkdir` instead of `/bin/mkdir` in activation scripts
2. **Config schema updates** - `telegram` → `channels.telegram`, `byProvider` → `byChannel`
3. **Memory slot fix** - Set `plugins.slots.memory: "none"` to disable default memory plugin
4. **Bundle extensions directory** - Copy extensions/ and docs/ to output, set `CLAWDBOT_BUNDLED_PLUGINS_DIR` env var (from upstream PR #25)

**Upstream PRs to file**:
- NixOS compatibility fixes (coreutils paths)
- Config schema updates for clawdbot 2026.1.x
- Reference upstream PR #25 for bundled plugins

---

## Next Steps

### Immediate
- [ ] **Test Telegram bot** - Send a message to verify clawdbot responds
- [ ] **File upstream PRs** - Contribute fixes back to `clawdbot/nix-clawdbot`

### Optional Improvements

1. **Rename server in Hetzner** (cosmetic):
   ```bash
   hcloud server update atmo-1-falk --name trainwreck
   ```

2. **Configure as remote builder** for other hosts:
   Add to suremac's nix config:
   ```nix
   nix.buildMachines = [{
     hostName = "trainwreck";  # or 100.68.122.74
     system = "aarch64-linux";
     sshUser = "chris";
     maxJobs = 8;
   }];
   nix.distributedBuilds = true;
   ```

3. **Add CI job** - Create `.builds/build-trainwreck.yml`

4. **Merge to main** - Once stable, merge trainwreck-wip branch

---

## Known Issues

### 1. Oracle/Summarize Plugins Disabled
The nix-steipete-tools flake (used by oracle/summarize plugins) references a different nixpkgs version that has corrupted store paths locally. These plugins are disabled in configuration.nix.

**To fix**: Run `sudo nix-store --verify --check-contents --repair` on your Mac, then re-enable the plugins.

### 2. Helix/Jujutsu Disabled
These programs require flake inputs (helix, starship-jj) that aren't available in the trainwreck flake. They're disabled with `lib.mkForce false`.

**To fix**: Add the required inputs to trainwreck's flake.nix if you want these tools on the server.

### 3. Doctor Warnings (non-blocking)
`clawdbot doctor` shows some warnings that don't prevent operation:
- Gateway auth is off (optional for local loopback)
- State directory permissions (cosmetic)
- Missing session/OAuth dirs (created on first use)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              trainwreck (Hetzner Cloud ARM VPS)             │
│              cax41: 16 cores, 32GB RAM, 320GB               │
│              IP: 49.13.143.249                              │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │   Tailscale     │    │         Clawdbot Gateway        │ │
│  │   (tailscale0)  │◄───│  - systemd user service ✅      │ │
│  │                 │    │  - nix-clawdbot fork            │ │
│  └────────┬────────┘    │  - Telegram channel             │ │
│           │             └─────────────────────────────────┘ │
│           │                                                 │
│           │             ┌─────────────────────────────────┐ │
│           │             │      Nix Remote Builder         │ │
│           │             │  - SSH access via tailnet       │ │
│           │             │  - aarch64-linux builds         │ │
│           └─────────────│  - Available to other hosts     │ │
│                         └─────────────────────────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Secrets (agenix)                     ││
│  │  - telegram-bot-token.age  ✅                           ││
│  │  - openrouter-api-key.age  ✅                           ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
           │
           │ Tailscale Mesh
           ▼
┌──────────────────┐     ┌──────────────────┐
│     suremac      │     │   trap/thorny    │
│  (your Mac)      │     │  (NixOS desktops)│
│                  │     │                  │
│  - Deploy from   │     │  - Use as remote │
│    here          │     │    builder       │
│  - Chat via      │     │                  │
│    Telegram      │     │                  │
└──────────────────┘     └──────────────────┘
```

---

## File Structure

```
flakes/hosts/trainwreck/
├── flake.nix                  # Host flake (aarch64-linux)
├── flake.lock                 # Pinned dependencies (uses fork)
├── configuration.nix          # NixOS system configuration
├── hardware.nix               # ARM64 hardware config
├── disko.nix                  # Disk partitioning
└── clawdbot-documents/        # AI personality files
    ├── AGENTS.md
    ├── SOUL.md
    └── TOOLS.md

flakes/base-lib/ssh-keys/default.nix  # Added suremac key
secrets/trainwreck/                    # Secrets directory
    ├── telegram-bot-token.age     # Bot token from @BotFather
    └── openrouter-api-key.age     # API key for AI models
secrets/secrets.nix                    # Updated with trainwreck entries
```

---

## Configuration Notes

### Enabled Features

- `age.secrets` - Configured and working, secrets decrypt on boot
- Tailscale - Connected to tailnet (100.68.122.74)
- `programs.clawdbot` - Running via forked nix-clawdbot
- Lingering enabled - Service persists after logout

### Disabled Programs

```nix
programs.helix.enable = lib.mkForce false;     # Needs helix flake input
programs.jujutsu.enable = lib.mkForce false;   # Needs starship-jj input
```

### Disabled Plugins

```nix
firstParty = {
  summarize.enable = false;  # Corrupted store path issue
  oracle.enable = false;     # Corrupted store path issue
  peekaboo.enable = false;   # No screen on headless server
};
```

---

## Deployment Commands

### Deploy from trainwreck itself (recommended for aarch64)
```bash
ssh chris@49.13.143.249
cd /tmp && rm -rf dotfiles-deploy
git clone --depth 1 -b trainwreck-wip https://git.sr.ht/~averagechris/dotfiles dotfiles-deploy
cd dotfiles-deploy
nom build ./flakes/hosts/trainwreck#nixosConfigurations.trainwreck.config.system.build.toplevel
sudo result/bin/switch-to-configuration switch
rm -rf /tmp/dotfiles-deploy
```

### Deploy from Mac (requires aarch64-linux builder)
```bash
# Using deploy-rs (needs remote builder configured)
nix run .#deploy -- .#trainwreck
```

### SSH Access
```bash
# Direct IP
ssh chris@49.13.143.249

# Via Tailscale (once MagicDNS works)
ssh chris@trainwreck
```

### Check Service Status
```bash
ssh chris@49.13.143.249 'systemctl --user status clawdbot-gateway'
```

---

## Task Checklist

### Phase 1: Infrastructure Setup ✅
- [x] Create trainwreck host directory structure
- [x] Write flake.nix with required inputs
- [x] Write hardware.nix for ARM64
- [x] Write disko.nix for disk partitioning
- [x] Write configuration.nix with base modules
- [x] Add trainwreck to top-level flake.nix
- [x] Add suremac SSH key to base-lib

### Phase 2: VPS Provisioning ✅
- [x] Use existing Hetzner VPS (atmo-1-falk / cax41)
- [x] Install NixOS via nixos-anywhere
- [x] Verify NixOS is running

### Phase 3: Access & Networking ✅
- [x] Fix SSH access as chris user
- [x] Rebuild with updated SSH keys
- [x] Join Tailscale network (100.68.122.74)
- [x] Verify Tailscale connectivity

### Phase 4: Secrets & Clawdbot ✅
- [x] Create Telegram bot via @BotFather
- [x] Get Telegram user ID via @userinfobot (7281917558)
- [x] Get trainwreck host SSH key for agenix
- [x] Create telegram-bot-token.age
- [x] Create openrouter-api-key.age
- [x] Fork nix-clawdbot to SourceHut
- [x] Apply NixOS fixes to fork
- [x] Update trainwreck flake.nix to use fork
- [x] Deploy with forked nix-clawdbot
- [x] Clawdbot gateway running and stable
- [x] Enable lingering for service persistence
- [ ] Verify clawdbot responds on Telegram
- [ ] File upstream PRs with NixOS fixes

### Phase 5: Remote Builder Setup
- [ ] Configure trainwreck as remote builder
- [ ] Add trainwreck to other hosts' build machines
- [ ] Test remote build from suremac

### Phase 6: CI & Cleanup
- [ ] Add build-trainwreck.yml to .builds/
- [ ] Rename server to trainwreck in Hetzner
- [ ] Merge trainwreck-wip to main
- [ ] Remove/archive this plan.md

---

## References

- [Clawdbot Docs](https://docs.clawd.bot/)
- [nix-clawdbot GitHub](https://github.com/clawdbot/nix-clawdbot)
- [nix-clawdbot Fork](https://git.sr.ht/~averagechris/nix-clawdbot)
- [Upstream PR #25 - Bundle extensions](https://github.com/clawdbot/nix-clawdbot/pull/25)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [disko](https://github.com/nix-community/disko)
