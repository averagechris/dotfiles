# trainwreck / Openclaw

`trainwreck` is an aarch64-linux Hetzner VPS. Its main special workload is
Openclaw, a Telegram AI assistant, configured from
`flakes/hosts/trainwreck/configuration.nix`.

## Openclaw instances

There are two Openclaw gateway instances:

| Instance | Service | Purpose |
|----------|---------|---------|
| `grem` | `openclaw-gateway-grem.service` | Production bot |
| `grem-staging` | `openclaw-gateway-grem-staging.service` | Testing config changes |

Make config changes to `instances.grem-staging` first, deploy, and test with the
staging Telegram bot. After verification, copy the change to `instances.grem`
and deploy again.

The Home Manager Openclaw package overrides `meta.priority = 10`. Keep this
override: the Openclaw bundle and the shared shell Python both expose
`bin/python-config`, and equal-priority installation causes `home-manager-path`
buildEnv collisions during trainwreck builds.

## Service management

Useful commands when connected to `trainwreck`:

```bash
# Production bot
systemctl --user status openclaw-gateway-grem.service
systemctl --user restart openclaw-gateway-grem.service
journalctl --user -u openclaw-gateway-grem.service -f

# Staging bot
systemctl --user status openclaw-gateway-grem-staging.service
systemctl --user restart openclaw-gateway-grem-staging.service
journalctl --user -u openclaw-gateway-grem-staging.service -f
```

SSH access from `suremac` requires the current trainwreck public IP; ask the user
for it. Other hosts can usually use `ssh chris@trainwreck` over Tailscale.

## Directory structure on trainwreck

| Path | Purpose |
|------|---------|
| `~/.openclaw-grem/` | Grem production state directory |
| `~/.openclaw-grem/openclaw.json` | Config symlink pointing into the Nix store |
| `~/.openclaw-grem/runtime/openclaw-grem.json` | Generated runtime config |
| `~/.openclaw-grem/extensions/` | Symlink to `~/dotfiles/flakes/hosts/trainwreck/clawdbot-extensions/` |
| `~/.openclaw-grem/telegram/` | Telegram session state |
| `~/.openclaw-grem/agents/` | Agent configurations |
| `~/.openclaw-grem/workspace/` | Workspace files |
| `/tmp/openclaw/openclaw-gateway.log` | Service log file |

## Encrypted personality documents

Grem's personality documents are encrypted with agenix and may contain personal
or sensitive information. Do not read decrypted copies or `.age` files unless the
user explicitly asks you to.

| Secret | Purpose |
|--------|---------|
| `secrets/trainwreck/grem-AGENTS.md.age` | Agent instructions, security protocol, multi-user awareness |
| `secrets/trainwreck/grem-SOUL.md.age` | Personality, identity, relationship context |
| `secrets/trainwreck/grem-TOOLS.md.age` | Tool documentation and usage guidelines |

For a human editing session:

```bash
cd ~/dotfiles/secrets
agenix -e trainwreck/grem-AGENTS.md.age
agenix -e trainwreck/grem-SOUL.md.age
agenix -e trainwreck/grem-TOOLS.md.age
```

The documents are decrypted at activation time and symlinked into
`~/.openclaw-grem/workspace/`.

## Custom extensions

Extensions live in `flakes/hosts/trainwreck/clawdbot-extensions/`:

- `kagi-search/` - Kagi search integration
- `meme-generator/` - Meme generation
- `image-generator/` - AI image generation
- `opencode-delegate/` - Delegate coding tasks to OpenCode

After changing extensions, make sure the checkout on `trainwreck` receives the
new revision before restarting the relevant service. Agents should ask before
running remote login, remote VCS, or service restart commands.

## Session isolation

Each DM conversation gets its own isolated session via `session.dmScope =
"per-peer"`. Group chats have their own sessions separate from DMs.

`session.identityLinks` can intentionally share one identity across platforms,
for example Telegram, Discord, Signal, or Slack. Keep private platform IDs in the
host config or encrypted material rather than copying them into public docs.

## Deployment

Use the standard deploy-rs workflow from [deploy](/docs/deploy.md) with the
`trainwreck` target:

```bash
nix run .#deploy -- .#trainwreck
nix run .#deploy-quiet -- trainwreck
```

`trainwreck` is aarch64-linux, so its deploy-rs activation wrapper must also be
`aarch64-linux`; see the deploy doc for the architecture failure mode.

`trainwreck` is also enrolled in the pull-based `dotfiles.selfDeploy` module. It
waits 120 minutes after boot, then checks every six hours with a 30-minute
randomized delay. This intentionally runs after `thorny` has had time to warm the
current `trainwreck` system closure through its host build-cache timer.

The self-deploy service currently waits for these system units to be active after
activation, and rolls back to the previous system if they are not:

- `sshd.service`
- `tailscaled.service`
- `nix-daemon.service`
- `caddy.service`

Openclaw gateway checks are intentionally left for the planned future smart
post-activation checks, because those are Home Manager user units and should be
validated with richer host-specific logic than the initial system-unit health
gate.

Useful checks on `trainwreck`:

```bash
systemctl status dotfiles-trainwreck-self-deploy.timer
systemctl status dotfiles-trainwreck-self-deploy.service
journalctl -u dotfiles-trainwreck-self-deploy.service
```

If deploy-rs is unavailable, rebuild on trainwreck directly only after confirming
the desired remote workflow with the user.

## Build notes

`openclaw-gateway` uses upstream `nix-openclaw`'s `fetchPnpmDeps`, which by
default downloads every platform variant of large optional native packages
(Claude agent SDK, OpenAI Codex, GitHub Copilot, node-llama-cpp, etc.).
`flakes/hosts/trainwreck/openclaw-overlay.nix` removes `--force` from the
fetcher so pnpm only downloads the aarch64-linux variants, shrinking the
download from multi-GB to a fraction of that. The overlay also rebuilds the
`openclaw` bundle on top of the patched gateway. Keep the overlay in
`flakes/hosts/trainwreck/flake.nix` unless upstream resolves this.

### Building natively on trainwreck

The `openclaw-gateway` TypeScript build is CPU-intensive. When built on the
`thorny` remote builder via QEMU emulation, it can take 20+ minutes. Building
natively on trainwreck (aarch64-linux) is much faster (~3 minutes for the
`tsdown` step).

To build and activate directly on trainwreck:

```bash
# Sync dotfiles to trainwreck first (rsync or git), then:
ssh chris@trainwreck 'cd ~/dotfiles && git add -A'
ssh chris@trainwreck 'sudo nixos-rebuild switch --flake ~/dotfiles#trainwreck'
```

If Home Manager fails with "Existing file '.../openclaw.json' would be
clobbered", remove the old config symlinks and re-run:

```bash
ssh chris@trainwreck 'rm ~/.openclaw-*/openclaw.json'
ssh chris@trainwreck 'sudo nixos-rebuild switch --flake ~/dotfiles#trainwreck'
```
