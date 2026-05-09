# Thorny / thelio-nixos

`thorny` is the System76 Thelio desktop formerly known on the network as
`thelio-nixos`. Its primary role is a high-core-count Nix remote builder and
SSH workstation, while still providing a GUI that feels close to `tater` when
used locally.

## Role

- Remote Nix builder reachable over Tailscale/SSH.
- Local desktop workstation with the shared Hyprland setup used by `tater`.
- Desktop/gaming-capable machine; it keeps Steam, GameMode, 32-bit graphics,
  controller support, Podman, and libvirt enabled.

## Remote builder configuration

The host imports `nixosModules.isRemoteBuilder`, which authorizes the system SSH
keys listed in `sshKeys.usesRemoteBuilders` to log in as `chris` for remote
build submissions.

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
