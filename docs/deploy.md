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

## Activation wrapper architecture

The shared `mkDeploy` helper selects the deploy-rs activation wrapper for the
target host architecture. Keep this architecture selection intact for non-x86
hosts such as `trainwreck`; using an x86_64 activation wrapper for an aarch64
host copies a non-ARM binary to the host and fails during activation with
`cannot execute binary file: Exec format error`.
