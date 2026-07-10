# LAN SSH Discovery and Safe Helpers

The dotfiles shell profile installs DHCP-friendly LAN SSH helpers for machines
whose local IP address changes often and therefore should not be pinned in
`known_hosts` by address.

## Commands

```bash
dotfiles-lan-hosts          # scan likely local IPv4 addresses and print HOST<TAB>IP
dotfiles-lan-hosts thorny   # filter to one host name
dotfiles-lan-hosts --ip thorny
dotfiles-lan-hosts --no-cache --ip thorny

ssh-lan thorny              # discover thorny's current LAN IP, then SSH safely
ssh-lan thorny -- hostname
ssh-thorny-lan -- hostname  # convenience wrappers for thorny/tater/suremac
ssh-tater-lan
ssh-suremac-lan
```

`ssh-lan` and the host wrappers use the same noninteractive, LAN-safe SSH policy
used by agents during temporary measurement work:

```text
BatchMode=yes
PasswordAuthentication=no
ConnectTimeout=2
ConnectionAttempts=1
StrictHostKeyChecking=yes
UserKnownHostsFile=<generated fleet-key file>
GlobalKnownHostsFile=/dev/null
CheckHostIP=no
UpdateHostKeys=no
HostKeyAlgorithms=ssh-ed25519
```

`StrictHostKeyChecking` is actually set to `yes`: discovery uses an immutable
generated `known_hosts` file containing the configured fleet host keys, while
the final `ssh-lan HOST` connection uses only that host's key. The wildcard in
the generated file binds the trusted key rather than a volatile DHCP address.
An unrelated machine can claim to have hostname `thorny`, but it cannot pass the
final connection's host-key check without thorny's private host key.

This avoids writing volatile DHCP addresses to the user's normal `known_hosts`
without giving up host authentication. For stable public or tailnet names, keep
using normal SSH configuration and host-key persistence.

The discovery helper refuses to scan unless an active `/24` is in
`DOTFILES_LAN_TRUSTED_SUBNETS`, which defaults to the home LAN
`192.168.4`. This also prevents unrelated VPN or public-interface prefixes from
being scanned. Add another trusted LAN explicitly, or use
`DOTFILES_LAN_ALLOW_UNTRUSTED=1` for a deliberate one-off bypass. The bypass is
still noisy on public networks because it exposes SSH probe metadata and may
trigger network monitoring, but fleet host-key verification remains enforced.

## Discovery behavior

`dotfiles-lan-hosts` derives likely `/24` scan prefixes from the current network
interfaces and also falls back to the current home LAN prefix `192.168.4`. It
identifies a host by making a short, key-only SSH probe and reading `hostname`.
Only servers presenting one of `dotfiles.shell.lanSsh.hostKeys` are accepted by
discovery. The default map contains thorny, tater, and suremac keys from
`flakes/base-lib/ssh-keys/default.nix`; update that source when a host key rotates.
For a named lookup, addresses in `dotfiles.shell.lanSsh.hostHints` are
authenticated first and a full `/24` scan runs only if those hints miss. Thorny's
current `192.168.4.28` address is the default hint, reducing a cold lookup from a
multi-wave subnet scan to one authenticated probe. Host-specific lookups use
separate cache entries so a fast partial result cannot hide other fleet hosts.
Restarting thorny or the router usually preserves the DHCP lease, but the hint
may become stale if the lease changes. A stale hint is safe: no response or a
different host key is rejected, then discovery falls back to the authenticated
`/24` scan and caches the address it finds. The configured bootstrap hint remains
`.28`, so after cache expiry a moved host pays one failed hint probe before the
full scan.
Successful scans are cached for one hour per local network and SSH user, so
repeated aliases avoid rescanning the `/24`. The cache key fingerprints local
addresses, the default route, and the Wi-Fi or NetworkManager connection when
the platform exposes it, so changing networks selects a fresh cache. Pass
`--no-cache` to force a fresh scan; the fresh results replace the cache. Cache
files live under `${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles`.

Useful overrides:

```bash
DOTFILES_LAN_SUBNETS="192.168.4 192.168.5" dotfiles-lan-hosts
DOTFILES_LAN_TRUSTED_SUBNETS="192.168.4 192.168.5" dotfiles-lan-hosts
DOTFILES_LAN_IPS="192.168.4.28" dotfiles-lan-hosts --ip thorny
DOTFILES_LAN_SCAN_JOBS=32 dotfiles-lan-hosts
DOTFILES_LAN_CACHE_TTL=300 dotfiles-lan-hosts
DOTFILES_LAN_SSH_CONNECT_TIMEOUT=5 ssh-lan thorny
DOTFILES_LAN_SSH_USER=chris ssh-lan tater
```

Configure additional likely addresses in Home Manager when they become useful:

```nix
dotfiles.shell.lanSsh.hostHints = {
  thorny = ["192.168.4.28"];
  tater = ["192.168.4.42"];
};
```

## Key trust between hosts

NixOS hosts using the shared `chrisMinimal` user module authorize the public keys
listed in `sshKeys.chris`, which includes suremac's user key and thorny's legacy
`thelio` user key. That means suremac can SSH to tater/thorny as `chris`, and
thorny's user key can SSH to tater/thorny as `chris`.

`suremac` enables macOS Remote Login through nix-darwin and authorizes:

- thorny's `chris.thelio` user key
- tater's `system.tater` host key, for host-level automation that explicitly uses
  `/etc/ssh/ssh_host_ed25519_key`

If tater gets a dedicated `chris@tater` user SSH key, add it to
`flakes/base-lib/ssh-keys/default.nix` as `chris.tater` and include it in
suremac's authorized keys so normal user-initiated SSH from tater to suremac does
not need the host key identity.
