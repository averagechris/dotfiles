# trainwreck

`trainwreck` is an aarch64-linux Hetzner VPS. It is kept as a small server host
for SSH, Tailscale, deploy/self-deploy plumbing, Caddy's public `hister` reverse
proxy, and lightweight agent tooling.

The previous Telegram bot stack was removed from this host because it was not in
active use and its gateway dependency graph made trainwreck builds
disproportionately slow. Do not reintroduce the old gateway services, extension
trees, or personality document plumbing here. Future bot work should use the
planned `workctl` + `goodbot` path once those projects are ready.

SSH access from `suremac` requires the current trainwreck public IP; ask the user
for it. Other hosts can usually use `ssh chris@trainwreck` over Tailscale.

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

Useful checks on `trainwreck`:

```bash
systemctl status dotfiles-trainwreck-self-deploy.timer
systemctl status dotfiles-trainwreck-self-deploy.service
journalctl -u dotfiles-trainwreck-self-deploy.service
```

If deploy-rs is unavailable, rebuild on trainwreck directly only after confirming
the desired remote workflow with the user.
