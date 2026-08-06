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
- on macOS, points Cargo's Apple-target link step at a fast-linker dispatcher
  (Apple's new `ld` when manually installed, otherwise nixpkgs `lld`; see
  [Rust linker on macOS](#rust-linker-on-macos));
- when OpenCode is enabled, injects `CARGO_INCREMENTAL=0` into OpenCode shell
  executions so isolated agent workspaces share complete crate outputs through
  sccache while ordinary interactive shells keep incremental compilation;
- starts a clean `sccache-server` daemon at login (launchd agent on macOS,
  systemd user service on Linux);
- runs a periodic `dev-cache-cleanup` job (launchd on macOS, systemd user timer
  on Linux; daily by default via `cleanup.intervalSeconds`). On macOS a cheap
  wrapper wakes more often and runs the full cleanup only when it is due and the
  machine has CPU headroom and no conflicting clients;
- runs a lightweight low-disk checker (`dev-cache-low-disk-cleanup`) that wakes
  more frequently and only starts cleanup when `/` falls below the configured
  free-space threshold.

## sccache server startup

The service starts the normal sccache daemon with `SCCACHE_IDLE_TIMEOUT=0` from
the service manager's clean environment, stopping any rogue server first. The
daemon then stays alive and serves Cargo clients from normal shells and nix
shells.

On macOS, the launchd job raises the daemon's soft open-file limit from
launchd's default 256 to 16384. sccache hashes compiler inputs in parallel, and a
broad build of a large generated crate such as `aws-sdk-s3` can otherwise fail
inside sccache with `Too many open files (os error 24)`, even though the same
interactive shell has a much higher limit. Reducing `CARGO_BUILD_JOBS` or
clearing `RUSTC_WRAPPER` can hide that service-limit problem, but should not be
needed after the launchd limit is applied.

This exists because sccache's default behavior is to lazily start the server
from whichever compile happens first, inheriting that process's environment
permanently. On macOS, a server started inside a nix shell (where
`DEVELOPER_DIR` points at the nix Apple SDK) poisons every later C-compile that
goes through `/usr/bin/cc`'s xcselect shim — cc-rs wraps the C compiler with
sccache when `RUSTC_WRAPPER` is set — failing with:

```
sccache: caused by: Compiler not supported: "error: tool 'clang' not found"
```

Do not configure launchd `KeepAlive` or systemd `Restart=always` around
`sccache --start-server`: that command daemonizes and exits after spawning the
real server. A restart loop repeatedly runs the startup script, whose
`sccache --stop-server` handoff kills the healthy daemon; Cargo clients racing
that loop warn:

```
sccache: warning: The server looks like it shut down unexpectedly, compiling locally instead
```

If the Apple SDK poisoning error ever reappears, restart the managed service so
the replacement daemon comes from the clean service environment rather than the
next arbitrary Cargo client:

```bash
# macOS
sccache --stop-server || true
launchctl kickstart gui/$(id -u)/org.nix-community.home.sccache-server

# Linux
systemctl --user restart sccache-server
```

Check the service with the macOS `launchctl print` command above or with
`systemctl --user status sccache-server` on Linux.

For macOS descriptor-limit diagnosis, the generated plist should set
`NumberOfFiles` to 16384 under `SoftResourceLimits`. Apply Home Manager again if
the live plist predates that setting.

Logs: `~/Library/Logs/sccache-server.log` on macOS; the user journal on Linux.

## Agent and manual Cargo checks

On hosts with `dotfiles.devCache.enable`, Rust checks should use the configured
wrapper. Do not run routine commands as `RUSTC_WRAPPER= cargo ...` or
`env RUSTC_WRAPPER= cargo ...`: Cargo gives that empty environment variable
precedence over `~/.cargo/config.toml`, so it disables sccache even though the
module configured `rustc-wrapper` and a supervised server.

The clean service-started daemon is the durable fix for the historical macOS
`DEVELOPER_DIR`/Apple SDK poisoning failure described above. If a Cargo command
fails in a way that specifically implicates sccache, first capture the error and
restart the managed service with the commands above. As an explicit one-command
escape hatch, use `SCCACHE_DISABLE=1 cargo ...` and mention the observed sccache
failure in the handoff. Prefer that over clearing `RUSTC_WRAPPER`, because it
keeps the configured wrapper visible and prevents the workaround from becoming
the default pattern.

By default, `sccache.disableOpencodeIncremental = true` installs the global
OpenCode plugin `dotfiles-rust-cache.js`. Its `shell.env` hook sets
`CARGO_INCREMENTAL=0` for AI tool commands and OpenCode user terminals. Cargo
still performs normal target freshness checks, but changed crates are compiled
as complete cacheable outputs rather than workspace-local incremental outputs.
This favors clean and short-lived parallel agent workspaces. Cargo commands in
ordinary terminals retain the default incremental edit/build loop. An explicit
inline `CARGO_INCREMENTAL=1 cargo ...` can opt an individual OpenCode command
back into workspace-local incremental compilation.

Because agents working in other repositories never read this document, the
OpenCode `rust-cargo` skill carries the agent-facing rules (concise cargo
output flags, no `-j` throttling, rerun timed-out builds, never clear
`RUSTC_WRAPPER`). When `dotfiles.devCache` is enabled, this module appends a
host-specific appendix to that skill with the managed-server restart commands
and the `CARGO_INCREMENTAL=0` policy.

## Cleanup job phases

## Rust linker on macOS

`rustLinker.enable` (default: on for Darwin) adds `[target.aarch64-apple-darwin]`
and `[target.x86_64-apple-darwin]` sections to the generated
`~/.cargo/config.toml` with
`rustflags = ["-C", "link-arg=--ld-path=<dispatcher>"]`. Every cargo/rustc
invocation on the machine — dev shells, rustup toolchains, `cargo install`,
rust-analyzer, agent builds — links through the dispatcher script.

Rationale: nixpkgs can only ship the open-source *classic* ld64, the slowest
Mach-O linker still in common use; Apple's fast rewritten linker ("ld-prime",
Xcode 15+, `PROJECT:ld64-` versions >= 1000) is closed-source and cannot be
packaged. sccache never caches the link step, so linking dominates warm
iterative builds. lld and ld-prime are both several times faster than classic
ld64 and roughly comparable to each other.

The dispatcher (`dotfiles-rust-ld-dispatch`) chooses at link time:

1. `/Library/Developer/CommandLineTools/usr/bin/ld`, then
   `/Applications/Xcode.app/.../XcodeDefault.xctoolchain/usr/bin/ld`, if
   present **and** reporting a new-linker version (classic prints
   `PROJECT:ld64-9xx`; ld-prime prints `PROJECT:ld-1015.7` or higher — the
   dispatcher accepts either spelling with version >= 1000). A manually
   installed current Xcode CLT is picked up automatically with no Home
   Manager switch; classic Apple installs are never preferred.
2. Otherwise nixpkgs `ld64.lld`.

Notes:

- Enabling this changes target rustflags, which are part of Cargo's
  fingerprint, so expect a one-time rebuild per project (largely absorbed by
  sccache).
- A project's own `[target.*] rustflags` or a `RUSTFLAGS` environment variable
  *replaces* (not merges with) this configuration; such projects keep their
  existing linker setup.
- `--ld-path` requires the linker driver to be clang >= 12, which holds for
  both nix cc-wrappers and Apple clang.

### Installing the fast Apple linker (recommended on new Macs)

lld works out of the box with no manual steps. To get Apple's ld-prime —
occasionally faster, and what the dispatcher prefers — install the Xcode
Command Line Tools once per machine:

```bash
xcode-select --install
```

Do **not** run `xcode-select -s` afterwards: the developer-directory pointer
should stay whatever the nix toolchain expects, and the dispatcher finds the
CLT by absolute path (`/Library/Developer/CommandLineTools/usr/bin/ld`), so no
switch is needed. The next link picks it up automatically — no Home Manager
switch, no rebuild (linker identity is not part of Cargo's fingerprint).

Verify what the dispatcher will use:

```bash
"$(sed -n 's/.*--ld-path=\([^"]*\).*/\1/p' ~/.cargo/config.toml | head -n 1)" -v 2>&1 | head -n 1
```

After the CLT install this should print `PROJECT:ld-<version>` (ld-prime's
spelling; >= 1015); before, it prints an `ld64.lld` usage error. Any
current CLT qualifies; if macOS ever offers a CLT update notification, taking
it is fine. This is intentional per-machine imperative state, like the other
manually installed apps.

## Cleanup job phases

Logs: `~/Library/Logs/dev-cache-cleanup.log` on macOS;
`journalctl --user -u dev-cache-cleanup` on Linux. The low-disk checker logs to
the same macOS file and to `journalctl --user -u dev-cache-low-disk-cleanup` on
Linux, but stays quiet while free space is healthy.

Each full cleanup run:

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
6. **Low-disk pressure cleanup** (`cleanup.lowDisk`, default off) — on hosts
   that opt in, after the normal phases, if `/` still has less than
   `cleanup.lowDisk.minFreeGiB` available, the job escalates:
   - runs `nix-collect-garbage -d` to remove old user profile rollback
     generations, then `nix store gc` for unreferenced store paths;
   - re-runs `cargo-sweep` with the tighter
     `cleanup.lowDisk.cargoSweepStaleDays` window;
   - prunes Docker/OrbStack builder cache with the tighter
     `cleanup.lowDisk.dockerBuilderMaxUsedSpace` and
     `cleanup.lowDisk.dockerRetention` settings;
   - posts a macOS notification when the pressure phase starts.

When enabled, the separate low-disk checker runs every
`cleanup.lowDisk.checkIntervalSeconds` (30 minutes by default) and only invokes
the full cleanup when `/` is already below `cleanup.lowDisk.minFreeGiB` (30 GiB
by default). The full cleanup also uses a simple lock so the periodic and
low-disk triggers do not overlap.

The cleanup helpers are installed in the user profile for manual use:

```bash
dotfiles-dev-cache-cleanup            # normal cleanup, escalates only if still below threshold
dotfiles-dev-cache-cleanup --pressure # force the pressure phase after normal cleanup
dotfiles-dev-cache-low-disk-cleanup   # cheap threshold check, then cleanup only if low
```

## macOS load-aware scheduling

macOS cleanup launchd agents do not wake a sleeping laptop. Instead of relying
on a fixed overnight wall-clock time, the normal cleanup agent runs at
`cleanup.retryIntervalSeconds` (15 minutes by default), checks a timestamp, and
exits immediately unless the full `cleanup.intervalSeconds` cadence is due. If
the laptop was asleep or the due check lands in a busy window, the timestamp is
not advanced and the next eligible interval while awake can use available
headroom.

The shared readiness check does not invoke Nix or query its SQLite database. It
takes one `ps` snapshot and reads macOS's one-minute load average and logical CPU
count with `sysctl`. Maintenance is allowed while the user is active—including
during meetings—when load is below 60% of logical CPU capacity. Active Nix,
nix-darwin, or Home Manager clients always defer maintenance to avoid store and
SQLite contention. The always-resident `nix-daemon` is ignored; a
`nix-daemon --stdio` remote-store connection is treated as active. If process or
load inspection fails, the check fails closed and launchd retries later.

All scheduled cleanup checks additionally defer for active Cargo, Rust, and
Docker clients because cleanup can delete those tools' cache artifacts. The
low-disk checker runs the normal phases first and only escalates to pressure
cleanup if disk space is still low. It keeps its independent, usually more
frequent retry interval. A failed `df` inspection is treated as unknown rather
than as zero free space.

GC and the suremac self-update also share the PID-aware `shlock` lock at
`~/.local/state/dotfiles-nix-maintenance/lock`. This prevents both maintenance
jobs from starting after they observe the same ready instant; stale PID locks are
reclaimed by `shlock`. The check is advisory for ordinary
commands—a new interactive Nix command can still begin after it passes—but it
eliminates maintenance-versus-maintenance overlap.

Direct `dotfiles-dev-cache-cleanup` invocations are explicit manual requests, so
they bypass the readiness check while still respecting the shared lock. Scheduled
deferrals are logged to `~/Library/Logs/dev-cache-cleanup.log` and do not consume
the full-cleanup interval.

## Host configuration

| Host | Notes |
|------|-------|
| suremac | `sccache.cacheSize = "100G"`; full cleanup due every 6h with a cheap 5m load/headroom retry; low-disk check every 15m with a 10 GiB threshold; Nix user generation and Cargo sweep retention reduced to 3d; sweep roots `~/projects` and `~/sureapp`; Docker pruning against OrbStack with `pruneVolumes = true` |
| tater | Defaults; docker phase enabled, prunes via the real docker daemon |
| thorny | Defaults with `docker.enable = false` (podman host, little container churn) |

`suremac` note: the OrbStack `workd-dev` NixOS VM used by `workctl` keeps its
own nix store inside the VM's disk image, which grows with rebuilds. Run
`nix-collect-garbage -d` inside the VM occasionally; OrbStack reclaims the
freed space from the disk image automatically.
