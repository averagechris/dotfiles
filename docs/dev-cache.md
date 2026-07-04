# Dev Cache (`dotfiles.devCache`)

Home Manager module (`flakes/hm-modules/modules/dev-cache.nix`) managing
development caches: a shared Rust compilation cache plus a periodic cleanup
job covering nix garbage, Cargo target artifacts, and Docker resources.
Rust is the current focus; future iterations may add Python and Node/JS
cache cleanups. Enabled on `suremac`, `tater`, and `thorny`.

## What it does

- installs `sccache` and configures Cargo with `rustc-wrapper = "sccache"`
  (`~/.cargo/config.toml` plus `RUSTC_WRAPPER`/`SCCACHE_DIR`/`SCCACHE_CACHE_SIZE`
  session variables);
- runs a supervised `sccache-server` (launchd agent on macOS, systemd user
  service on Linux);
- runs a periodic `dev-cache-cleanup` job (launchd on macOS, systemd user timer
  on Linux; daily by default via `cleanup.intervalSeconds`).

## sccache server supervision

The server runs in the foreground with `KeepAlive`/`Restart=always`,
`SCCACHE_IDLE_TIMEOUT=0`, and the service manager's clean environment, stopping
any rogue server on startup.

This exists because sccache's default behavior is to lazily start the server
from whichever compile happens first, inheriting that process's environment
permanently. On macOS, a server started inside a nix shell (where
`DEVELOPER_DIR` points at the nix Apple SDK) poisons every later C-compile that
goes through `/usr/bin/cc`'s xcselect shim — cc-rs wraps the C compiler with
sccache when `RUSTC_WRAPPER` is set — failing with:

```
sccache: caused by: Compiler not supported: "error: tool 'clang' not found"
```

If that error ever reappears, `sccache --stop-server` cures it immediately (the
supervisor restarts the server). Check the agent with
`launchctl list | grep sccache` (macOS) or
`systemctl --user status sccache-server` (Linux).

Logs: `~/Library/Logs/sccache-server.log` on macOS; the user journal on Linux.

## Cleanup job phases

Logs: `~/Library/Logs/dev-cache-cleanup.log` on macOS;
`journalctl --user -u dev-cache-cleanup` on Linux. Each run:

1. **sccache stats** — reported for visibility. sccache itself is bounded by
   `sccache.cacheSize` (LRU), so it needs no explicit cleanup.
2. **Nix GC** (`nixGc`, default on, 7-day window) — runs
   `nix-collect-garbage --delete-older-than 7d` unprivileged. This only deletes
   *user* profile generations (home-manager, `nix profile`) older than the
   window; root-owned system generations under `/nix/var/nix/profiles` are
   never removed, and every store path referenced by a remaining generation is
   a GC root, so the current and immediately previous system profiles always
   remain rollback targets.
3. **Root GC reminder** (`nixGc.rootGcReminder`, macOS only) — because
   unprivileged GC cannot trim darwin system generations, the job posts a
   macOS notification when more than `maxSystemGenerations` (default 10)
   accumulate. Handle it manually with:

   ```bash
   sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +5
   sudo nix-collect-garbage
   ```

   `--delete-generations +5` keeps the five most recent generations, so the
   previous darwin profile is never lost. On NixOS hosts system generations
   are trimmed by normal `nixos-rebuild` retention/boot-menu management or a
   system-level `nix.gc` if configured.
4. **Cargo sweep** (`cargoSweep`, default on, 7-day staleness) — runs
   `cargo-sweep sweep --recursive --time 7` over each directory in
   `cargoSweep.roots` (default `~/projects`). Unlike `cargo clean`, this
   deletes individual `target/` artifacts not used within the window and keeps
   recently used incremental caches. `--recursive` finds every Cargo target
   directory under a root, including nested managed jj workspaces such as
   `~/projects/ws/<repo>/<workspace>` and `~/sureapp/ws/<repo>/<workspace>`
   (hidden directories like `.git` are skipped). Worst case, swept artifacts
   are recompiled on the next build, mostly restored from sccache.
5. **Docker/OrbStack pruning** (`docker.enable`, default on) — prunes builder
   cache older than `docker.retention` while keeping it under
   `docker.builderMaxUsedSpace`, plus stopped containers, dangling images, and
   unused networks; `docker.pruneVolumes` optionally prunes unused volumes.
   Skips gracefully when no Docker-compatible daemon is running (e.g. podman
   hosts without the docker socket). Set `docker.enable = false` to drop the
   phase and the Docker CLI entirely.

## Host configuration

| Host | Notes |
|------|-------|
| suremac | `sccache.cacheSize = "50G"`; sweep roots `~/projects` and `~/sureapp`; Docker pruning against OrbStack with `pruneVolumes = true` |
| tater | Defaults; docker phase enabled, prunes via podman's docker-compatible socket when available |
| thorny | Defaults with `docker.enable = false` (podman host, little container churn) |

`suremac` note: the OrbStack `workd-dev` NixOS VM used by `workctl` keeps its
own nix store inside the VM's disk image, which grows with rebuilds. Run
`nix-collect-garbage -d` inside the VM occasionally; OrbStack reclaims the
freed space from the disk image automatically.
