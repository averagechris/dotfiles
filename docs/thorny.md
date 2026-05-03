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
- `nix.settings.min-free = 20 GiB`
- `nix.settings.max-free = 100 GiB`

This lets trusted SSH users submit builds and allows Nix to use the desktop's
available CPU cores. The free-space thresholds keep the existing shared 14-day
GC policy while letting Nix automatically free store paths if builder activity
pushes the disk toward low space. Client machines still need their own
`nix.buildMachines` entry pointing at `thorny`/`thelio-nixos`.

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

`tom`, `tater`, and `trap` import `nixosModules.useRemoteBuilds`. That shared
module configures distributed builds and includes `thorny` as an x86_64-linux
builder:

- Host aliases: `thorny`, `thelio-nixos`
- SSH identity: `/etc/ssh/ssh_host_ed25519_key`
- Known host key: `sshKeys.system.thelio`
- SSH fail-fast behavior: batch mode, one connection attempt, 5-second connect
  timeout, and short server-alive checks
- Builder settings: `maxJobs = 16`, `speedFactor = 4`
- Supported features: `benchmark`, `big-parallel`, `kvm`, `nixos-test`

Because the clients use their system SSH host key as the builder identity,
`thorny` must continue to authorize the keys in `sshKeys.usesRemoteBuilders`.
If another machine should use `thorny`, add its system key to that set and
import `nixosModules.useRemoteBuilds` on the client.

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
nixos-rebuild build --flake .#thorny
```

On the machine itself:

```bash
sudo nixos-rebuild switch --flake .#thorny
```

After the current configuration has been activated once, `thorny` supports
passwordless deploys from trusted SSH keys via `nixosModules.sudoDeploy` and
`dotfiles.sudoNoPassword.enable = true`. Use deploy-rs from this repository:

```bash
nix run .#deploy -- .#thorny
```

This relies on SSH access as `chris`; `chris` is in `wheel`, and wheel sudo does
not require a password on this deployable builder host.
