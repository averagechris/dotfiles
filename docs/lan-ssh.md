# LAN SSH Discovery and Safe Helpers

The dotfiles shell profile installs DHCP-friendly LAN SSH helpers for machines
whose local IP address changes often and therefore should not be pinned in
`known_hosts` by address.

## Commands

```bash
dotfiles-lan-hosts          # scan likely local IPv4 addresses and print HOST<TAB>IP
dotfiles-lan-hosts thorny   # filter to one host name
dotfiles-lan-hosts --ip thorny

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
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
CheckHostIP=no
UpdateHostKeys=no
```

This intentionally avoids writing volatile DHCP addresses to `known_hosts`. Use
these helpers only for trusted local networks where ignoring host-key persistence
is acceptable. For stable public or tailnet names, keep normal SSH host-key
checking.

## Discovery behavior

`dotfiles-lan-hosts` derives likely `/24` scan prefixes from the current network
interfaces and also falls back to the current home LAN prefix `192.168.4`. It
identifies a host by making a short, key-only SSH probe and reading `hostname`.

Useful overrides:

```bash
DOTFILES_LAN_SUBNETS="192.168.4 192.168.5" dotfiles-lan-hosts
DOTFILES_LAN_IPS="192.168.4.28" dotfiles-lan-hosts --ip thorny
DOTFILES_LAN_SCAN_JOBS=32 dotfiles-lan-hosts
DOTFILES_LAN_SSH_CONNECT_TIMEOUT=5 ssh-lan thorny
DOTFILES_LAN_SSH_USER=chris ssh-lan tater
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
