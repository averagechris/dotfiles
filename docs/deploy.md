# Deployment

Use `nh` for local NixOS/Darwin builds and switches when possible. Use deploy-rs
for remote NixOS hosts that expose a deploy target.

## NixOS remote deploys

Deploy a host from the repository root:

```bash
nix run .#deploy -- .#<hostname>
```

For quieter agent-friendly output, use the wrapper. It accepts either a bare
hostname or a deploy-rs target, runs only the target host flake check by default,
then invokes deploy-rs with its broad checks skipped. Both phases buffer output
and print full logs only on failure:

```bash
nix run .#deploy-quiet -- <hostname>
nix run .#deploy-quiet -- --no-checks <hostname>
nix run .#deploy-quiet -- --deploy-rs-checks <hostname>
nix run .#deploy-quiet -- --show-output <hostname>
```

Host docs may include extra prerequisites, remote-builder notes, or recovery
paths. Check the relevant host doc before deploying.

## Darwin deploys

deploy-rs does not support Darwin hosts in this repository. For `suremac`, use
`nh darwin build` / `nh darwin switch` instead:

```bash
nh darwin build -q --no-nom . --hostname suremac
nh darwin switch . --hostname suremac
```

## Pull-based self-deploy

NixOS hosts can enroll in `dotfiles.selfDeploy`, a reusable pull-based updater
module. Enrolled hosts periodically check the current dotfiles `main` flake,
build their own `nixosConfigurations.<host>.config.system.build.toplevel`,
activate it with `switch-to-configuration switch`, then run local health checks.
If activation or health checks fail, the service switches back to the previously
running system.

This keeps deployment control host-local while still letting `thorny` do the
expensive work through the normal remote-builder/cache-warming path. The timers
are intentionally staggered so `thorny` has time to realize the current system
closures before lower-power hosts try to self-deploy.

Module shape:

```nix
dotfiles.selfDeploy = {
  enable = true;
  requiredSystemUnits = [
    "sshd.service"
    "tailscaled.service"
    "nix-daemon.service"
  ];
  timer = {
    onBootSec = "90m";
    onUnitActiveSec = "6h";
    randomizedDelaySec = "30m";
  };
};
```

Useful checks on an enrolled host:

```bash
systemctl status dotfiles-<host>-self-deploy.timer
systemctl status dotfiles-<host>-self-deploy.service
journalctl -u dotfiles-<host>-self-deploy.service
```

`thorny` keeps the historical service name
`dotfiles-thorny-self-deploy.service`. Its build-cache timer remains the fleet
cache warmer; self-deploy timers are the host-local activation layer.

For now health checks wait for explicit required system units to become active,
then require `systemctl is-system-running --quiet`. A future session should
extend the module with richer post-activation smart checks so hosts can inspect
application-level behavior, user units, HTTP endpoints, or other host-specific
assertions before accepting a generation.

## Activation wrapper architecture

The shared `mkDeploy` helper selects the deploy-rs activation wrapper for the
target host architecture. Keep this architecture selection intact for non-x86
hosts such as `trainwreck`; using an x86_64 activation wrapper for an aarch64
host copies a non-ARM binary to the host and fails during activation with
`cannot execute binary file: Exec format error`.
