# Thorny / thelio-nixos

`thorny` is the System76 Thelio desktop formerly known on the network as
`thelio-nixos`. Its primary role is a high-core-count Nix remote builder and
SSH workstation, while still providing a GUI that feels close to `tater` when
used locally.

## Role

- Remote Nix builder reachable over Tailscale/SSH.
- Local desktop workstation with the shared Hyprland setup used by `tater`.
- Desktop/builder machine with Podman and libvirt enabled. The old Steam,
  GameMode, and controller-support stack was removed because `thorny` is no
  longer used as a gaming box and those packages significantly inflate the
  workstation closure. 32-bit graphics support is disabled for the same reason;
  re-enable it only if Steam/Wine or another 32-bit graphics workload returns to
  thorny. With the chat/browser app trim already applied, disabling 32-bit
  graphics reduced the patched closure from about 10.9 GiB to 10.1 GiB.
- Signal and Helium are disabled on `thorny`. Chat/browser workflows live on
  `tater`/`suremac`; keeping those Electron/browser apps out of thorny's Home
  Manager profile leaves the local Hyprland session available without bloating
  the builder closure. The patched closure measured on `thorny` dropped from
  about 11.8 GiB to 10.9 GiB after disabling those apps and making the generated
  Hyprland config avoid retaining Signal when `programs.signal.enable = false`.
- Hourly scheduler for the homepage metadata refresh build on builds.sr.ht.
- Build-cache maintainer for active NixOS host system closures from dotfiles
  `main`, so client host switches can reuse work already realized by `thorny`.
- Cache warmer for fleet CI closures, pushing sourcehut `main` build outputs to
  the `averagechris-dotfiles` cachix cache so builds.sr.ht jobs substitute
  instead of building.
- Pull-based self-deployer for `thorny` itself, with post-activation health
  checks and automatic rollback to the previous running system on failure. The
  same reusable self-deploy module is used by enrolled server hosts such as
  `tom` and `trainwreck`; `thorny` remains the build/cache warmer rather than a
  central deploy-rs pusher.

## Remote builder configuration

The host imports `nixosModules.isRemoteBuilder`, which authorizes the system SSH
keys listed in `sshKeys.usesRemoteBuilders` to log in as `chris` for remote
build submissions.

`sshKeys.usesRemoteBuilders` also includes the `chris.suremac` user key so
suremac can run one-off SSH diagnostics and closure-size inspections against
thorny over the local network, even when the agent session is not on the
personal tailnet and therefore cannot use the usual `thorny`/`thelio-nixos`
MagicDNS names.

For DHCP-heavy LAN access, prefer `ssh-lan thorny` or `ssh-thorny-lan` from the
shared shell profile. Those helpers discover the current local IP and use
`UserKnownHostsFile=/dev/null`/`StrictHostKeyChecking=no` so changing LAN
addresses do not poison `known_hosts`; see [LAN SSH](/docs/lan-ssh.md).

The Nix daemon is configured for builder use:

- `nix.settings.trusted-users = ["@wheel" "chris"]`
- `nix.settings.max-jobs = "auto"`
- `nix.settings.cores = 0`
- `nix.settings.extra-platforms = ["aarch64-linux"]`
- `nix.settings.min-free = 20 GiB`
- `nix.settings.max-free = 100 GiB`

This lets trusted SSH users submit builds and allows Nix to use the desktop's
available CPU cores. The free-space thresholds keep the existing shared 14-day
GC policy while letting Nix automatically free store paths if builder activity
pushes the disk toward low space. Client machines still need their own
`nix.buildMachines` entry pointing at `thorny`/`thelio-nixos`.

## Homepage refresh scheduler

`thorny` runs `averagechris-site-refresh.timer` hourly with a small randomized
delay. The timer submits an unlisted builds.sr.ht job tagged
`averagechris.srht.site/cron/refresh-pages`; the submitted manifest runs
`nix run .#refresh-pages` in `~averagechris/averagechris.srht.site`, which only
publishes when the generated homepage/tools metadata differs from the live site.

The systemd service runs as `chris` and uses hut's normal user configuration from
`/home/chris/.config/hut/config`. Home Manager manages that config on `thorny`;
it contains an `access-token-cmd` that reads the agenix-decrypted SourceHut token
from `/run/agenix/hut-access-token`. The encrypted token lives at
`secrets/thorny/hut-access-token.age` and is registered in `secrets/secrets.nix`.

If the timer starts failing with authentication errors, confirm that the token
secret exists and is readable by `chris`, then test hut under the same account:

```bash
sudo -u chris hut meta show
```

Useful checks on `thorny`:

```bash
systemctl status averagechris-site-refresh.timer
systemctl status averagechris-site-refresh.service
journalctl -u averagechris-site-refresh.service
```

## Dotfiles host build cache

`thorny` runs `dotfiles-host-build-cache.timer` every six hours, with a 30-minute
randomized delay and persistent catch-up after downtime. The service builds the
current `main` branch of `~averagechris/dotfiles` for the active NixOS hosts:

- `trap`
- `thorny`
- `tom`
- `cruber`
- `tater`
- `trainwreck`

At the start of each run, before any Nix evaluation, the script resolves
SourceHut `main` exactly once with `git ls-remote`, validates that it is a
40-character Git revision, and uses that revision-pinned flake URL for every
host build. If `/var/lib/dotfiles-host-build-cache/last-successful-rev` already
matches that revision, the service exits immediately without evaluating Nix.

Each build uses a result link under `/var/lib/dotfiles-host-build-cache/results`,
which keeps the realized system closures available on `thorny` for later remote
builder clients and local switches. Per-host logs are written to
`/var/lib/dotfiles-host-build-cache/logs/<host>.log`; trainwreck also gets a
best-effort diagnostic dry-run planning log at
`/var/lib/dotfiles-host-build-cache/logs/trainwreck-dry-run.log`. Dry-run
diagnostic failures are reported but do not mask the actual trainwreck build
result. Revision-specific roots are built first; the canonical per-host links and
state marker switch only after all six hosts succeed. One host failure therefore
preserves the old successful revision, while per-host roots/logs still isolate
follow-up debugging. `suremac` is intentionally excluded because
Darwin systems are not built on Linux; inactive hosts such as `taz` and
`tootsie` are not part of the warm cache.

The service logs the effective revision/stage, Nix version, current system,
substituters, and builders at run start. It also emits elapsed timing for each
host, a combined five-host x86_64-linux total for `trap`, `thorny`, `tom`,
`cruber`, and `tater`, and a separate trainwreck aarch64/QEMU elapsed time. Use
those operational timings from thorny before concluding whether host builds
should be aggregated; result roots and logs remain per-host by default.

For a safe comparison of sequential x86 host planning versus one multi-installable
invocation at a pinned revision, run the focused harness outside normal service
execution:

```bash
nix run .#host-build-cache-benchmark -- --rev <40-char-sourcehut-main-rev>
```

The harness uses `nix build --dry-run` with the evaluation cache disabled for the
five x86 hosts. It alternates execution order across repeated trials and prints
elapsed seconds plus max RSS for the complete sequential loop and combined
multi-installable invocation. This compares planning/evaluation/substitution
shape, not realized build throughput. Keep trainwreck separate because its
aarch64/QEMU behavior answers a different performance question. Even dry-run
evaluation of all five systems can take tens of minutes; run it on thorny in an
intentional measurement window rather than in routine CI.

Useful checks on `thorny`:

```bash
systemctl status dotfiles-host-build-cache.timer
systemctl status dotfiles-host-build-cache.service
journalctl -u dotfiles-host-build-cache.service
ls -l /var/lib/dotfiles-host-build-cache/results
```

The old per-host SourceHut build manifests were removed because they duplicated
work that is more useful when performed on `thorny` itself.

## Fleet cache warmer

`thorny` runs `fleet-cache-warmer.timer` hourly, with a 10-minute randomized
delay and persistent catch-up after downtime. The service runs as `chris` and
pushes CI-relevant closures from sourcehut `main` branches to the
`averagechris-dotfiles` cachix cache, so builds.sr.ht jobs (which trust that
cache as a substituter) download instead of rebuilding:

- `~averagechris/averagechris.srht.site` → `#fleet-ci-closure`, the runtime
  closure of the `build-pages`/`refresh-pages` tooling used by the hourly
  refresh CI job.
- Each fleet repo (`linear-cli`, `slack`, `granola-cli`, `ctx`, `starship-jj`,
  `workctl`, `gander`) → `#release-artifact` for x86_64-linux.

For each target the warmer resolves the current `main` rev with
`git ls-remote`, skips it if that rev was already pushed, and otherwise runs
`nix build --no-link --print-out-paths` on the rev-pinned flake ref and pipes
the outputs to `cachix push averagechris-dotfiles`. A failure for one repo does
not stop the others; the service exits nonzero at the end if anything failed.
State (per-repo `last-pushed-*` rev files and the run lock) lives under
`/var/lib/fleet-cache-warmer/`.

The cachix auth token comes from the agenix secret
`secrets/cachix-auth-token.age`, exposed to `chris` at
`/run/agenix/cachix-auth-token`. The secret ships as the literal placeholder
`REPLACE_ME`, and the warmer logs "cachix token not provisioned yet; skipping"
and exits 0 until the real token is in place. To provision it:

1. Generate a write-capable token for the `averagechris-dotfiles` cache (from
   the cachix dashboard, or `cachix authtoken` output on a machine already
   authenticated).
2. Re-encrypt the secret with the real value using the normal recreate flow:

   ```bash
   ./secrets/recreate-secrets.sh cachix-auth-token.age
   ```

3. Deploy `thorny` (or wait for self-deploy) so agenix picks up the new
   ciphertext.

Useful checks on `thorny`:

```bash
systemctl status fleet-cache-warmer.timer
systemctl status fleet-cache-warmer.service
journalctl -u fleet-cache-warmer.service
ls -l /var/lib/fleet-cache-warmer
```

## Thorny self-deploy

`thorny` runs `dotfiles-thorny-self-deploy.timer` every two hours, with a
15-minute randomized delay and persistent catch-up after downtime. The service is
provided by the shared `dotfiles.selfDeploy` module. It checks latest `main` from
`~averagechris/dotfiles`; if that revision has not already been successfully
deployed, it builds:

```text
git+https://git.sr.ht/~averagechris/dotfiles?ref=main#nixosConfigurations.thorny.config.system.build.toplevel
```

The service records the previous `/run/current-system`, activates the new system
with `switch-to-configuration switch`, then verifies that these required units are
active:

- `sshd.service`
- `tailscaled.service`
- `nix-daemon.service`
- `NetworkManager.service`

It also requires `systemctl is-system-running --quiet` to pass. If activation or
the health check fails, it immediately switches back to the previous system. State
is kept under `/var/lib/dotfiles-thorny-self-deploy/` so repeated timer runs skip
the already-deployed revision and only ever attempt the latest `main`; there is no
per-commit deployment backlog.

Useful checks from another machine, especially `tater`:

```bash
thorny-status-remote
ssh thorny systemctl status dotfiles-thorny-self-deploy.timer
ssh thorny systemctl status dotfiles-thorny-self-deploy.service
ssh thorny journalctl -u dotfiles-thorny-self-deploy.service
```

Notifications are intentionally not wired in yet. If something feels off, use
`thorny-status-remote` first; it reports host health, active build-looking
processes, thermals, System76 power status, and Tailscale status.

The staggered fleet model is: `thorny` warms host system builds, then enrolled
hosts pull and activate their own latest system. `tom` waits 90 minutes after
boot before first self-deploy; `trainwreck` waits 120 minutes. Both repeat every
six hours with a 30-minute randomized delay.

`thorny` also enables `boot.binfmt.emulatedSystems = ["aarch64-linux"]` so it can
build `trainwreck`'s aarch64-linux system closure under QEMU/binfmt. This is
emulated native execution, not full Nix cross compilation, but it lets these
workflows succeed without needing an ARM workstation:

- Build `trainwreck` while SSH'd into `trainwreck`; the build is submitted back
  to `thorny` as a remote builder.
- Build `trainwreck` from x86_64 clients such as `tater` or `trap`; the client
  schedules aarch64-linux work on `thorny`.
- Build `trainwreck` directly on `thorny`; local aarch64-linux derivations run
  through binfmt/QEMU.

`thorny-status` is installed for quick SSH checks. It prints host uptime, load,
memory, disk usage, approximate Nix store size, active build-looking processes,
sensor output, System76 power service status, and Tailscale status:

```bash
thorny-status
```

On `tater`, `thorny-status-remote` runs the same check over SSH, defaulting to
the `thorny` Tailscale/DNS name:

```bash
thorny-status-remote
thorny-status-remote thelio-nixos
```

## Remote builder clients

`tom`, `tater`, `trap`, and `trainwreck` import `nixosModules.useRemoteBuilds`.
That shared module configures distributed builds and includes `thorny` as both an
x86_64-linux builder and an emulated aarch64-linux builder:

- Host aliases: `thorny`, `thelio-nixos`
- SSH identity: `/etc/ssh/ssh_host_ed25519_key`
- Known host key: `sshKeys.system.thelio`
- SSH fail-fast behavior: batch mode, one connection attempt, 5-second connect
  timeout, and short server-alive checks
- x86_64-linux builder settings: `maxJobs = 16`, `speedFactor = 4`
- x86_64-linux supported features: `benchmark`, `big-parallel`, `kvm`,
  `nixos-test`
- aarch64-linux builder settings: `maxJobs = 4`, `speedFactor = 1`
- aarch64-linux supported features: `benchmark`, `big-parallel`
- `nix.settings.builders-use-substitutes = true`, so `thorny` can fetch binary
  substitutes itself before falling back to local/emulated builds

The shared client module intentionally does not configure third-party remote
builders such as `eu.nixbuild.net`; `thorny` is the only remote builder managed
by this repository.

Because the clients use their system SSH host key as the builder identity,
`thorny` must continue to authorize the keys in `sshKeys.usesRemoteBuilders`.
If another machine should use `thorny`, add its system key to that set and
import `nixosModules.useRemoteBuilds` on the client.

`trainwreck`'s `/etc/ssh/ssh_host_ed25519_key.pub` is included in
`sshKeys.system.trainwreck` and `sshKeys.usesRemoteBuilders` for the "build while
SSH'd into trainwreck and remote to thorny" workflow. If that path fails with
`Permission denied`, confirm the public host key on `trainwreck` still matches
the repo-managed key, then rebuild `thorny` so the key lands in `chris`'s
authorized keys.

The client `nix.buildMachines` entry sets `sshKey =
"/etc/ssh/ssh_host_ed25519_key"` directly, so the Nix daemon does not depend on
root's SSH config to pick the right identity. If a client can SSH as your normal
user but remote builds fail with `Permission denied (publickey,keyboard-interactive)`,
compare `/etc/ssh/ssh_host_ed25519_key.pub` on the client with
`sshKeys.usesRemoteBuilders` and rebuild/switch `thorny` after adding the missing
system key.

The client module intentionally does not include old/offline x86_64 builders.
If `thorny` is asleep, offline, or unreachable from bad Wi-Fi, Nix should fail
the SSH attempt quickly and continue with local builds instead of waiting on a
long remote-builder retry path.

## Desktop alignment with tater

`thorny` uses the same broad desktop stack as `tater`:

- `nixosModules.hyprlandDesktop` instead of COSMIC.
- The pinned Hyprland input used by `tater` for compositor/portal consistency.
- `dotfiles.hyprland-workstation` with Ghostty as the terminal.
- Eww-oriented Hyprland setup with Waybar disabled.
- Hypridle/Hyprlock instead of the old swayidle/swaylock path.
- NetworkManager applet, Mega, Helium, Opencode, Yazi, and Claude Code.

Unlike `tater`, this is not a laptop, so it intentionally does **not** include
fingerprint, lid/clamshell, dock display profiles, Wi-Fi card mitigations,
automatic timezone travel behavior, or laptop battery/TLP tuning.

Hypridle is tuned for an always-available desktop/builder: it dims, locks, and
turns off displays after longer idle periods, but does not suspend or hibernate.

At the system level, sleep, suspend, hibernate, and hybrid-sleep targets are
disabled and logind's idle action is ignored. This keeps the machine reachable
for SSH and remote builds even if it was last used as a local desktop. Display
DPMS and screen locking are still handled by the Hyprland user session.

## Thermal and fan policy

`thorny` is allowed to get loud during remote builds. The desired behavior is
maximum throughput under load, followed by a return to quiet idle once the build
finishes.

The host explicitly enables System76 hardware support even though it no longer
uses the COSMIC desktop module:

```nix
hardware.system76.enableAll = true;
```

This keeps Thelio/System76 firmware and hardware integration active for fan and
power behavior. The host also installs monitoring tools for post-build checks:

- `lm_sensors` for CPU/GPU/fan sensor readings via `sensors`
- `nvme-cli` for NVMe health and temperature checks
- `smartmontools` for drive SMART data

Useful checks on the machine:

```bash
thorny-status
sensors
sudo nvme smart-log /dev/nvme0
sudo smartctl -a /dev/nvme0
systemctl status system76-power.service
```

Do not add laptop-oriented quieting such as TLP by default. If fan noise remains
high after builds complete, first check for lingering CPU load, System76 service
health, firmware updates, sensor readings, and dust from storage before adding a
custom fan-control daemon.

## Rebuild

From this repository:

```bash
nh os build . --hostname thorny
```

On the machine itself:

```bash
nh os switch . --hostname thorny
```

After the current configuration has been activated once, `thorny` supports
passwordless deploys from trusted SSH keys via `nixosModules.sudoDeploy` and
`dotfiles.sudoNoPassword.enable = true`. Use deploy-rs from this repository:

```bash
nix run .#deploy -- .#thorny
```

For quieter deploys, use the deploy wrapper. It accepts either a bare hostname or
deploy-rs target, runs only the target host flake check, then invokes deploy-rs
with its broad checks skipped. Both phases buffer output and print the full log
only on failure:

```bash
nix run .#deploy-quiet -- thorny
nix run .#deploy-quiet -- --no-checks thorny
nix run .#deploy-quiet -- --deploy-rs-checks thorny
nix run .#deploy-quiet -- --show-output thorny
```

This relies on SSH access as `chris`; `chris` is in `wheel`, and wheel sudo does
not require a password on this deployable builder host.

If deploy-rs prints `Interactive sudo is enabled` or prompts for `(sudo for
thorny) Password:`, check that `flakes/hosts/thorny/flake.nix` uses
`lib.mkDeploy`, not `lib.mkDeploy'`. The primed helper is reserved for hosts
that intentionally need interactive sudo during deployment.

## Remote builder smoke test

To prove that the active client is actually scheduling work on `thorny`, use a
fresh/unique derivation and disable local builds:

```bash
nom build --impure --no-link --max-jobs 0 -L --expr '
with import <nixpkgs> {};
runCommand "remote-builder-smoke-${toString builtins.currentTime}" {} "printf ok > $out"'
```

Expected output includes `building ... on 'ssh://chris@thorny'` and then copies
the resulting store path back from `ssh://chris@thorny`.

Do **not** use `--rebuild` as the remote-builder smoke test. `--rebuild` is a
local output check for an already-built derivation; with `--max-jobs 0` it can
fail with `local builds are disabled` even when remote builders are configured
and working. Use a unique derivation like the smoke command above when you need
to force a real remote build.
