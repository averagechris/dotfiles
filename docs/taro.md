# Taro

Personal MacBook Pro with Apple Silicon, 48 GiB RAM, macOS 26.5.1, and user
`chris`. nix-darwin sets its hostname to `taro` and manages the shell, Helix,
WezTerm, coding-agent tools, Colemak-DH, and build-cache cleanup. Windows float;
Raycast handles window shortcuts.

## Start with ChatGPT

Download [ChatGPT for macOS](https://learn.chatgpt.com/docs/app) first and sign in
with your personal OpenAI account. Ask the agent to set up this Mac using this
guide and the repository's `AGENTS.md`. Complete account sign-ins and macOS
permission prompts when needed.

## Install the native apps

Use current official downloads. Install app bundles in `/Applications` and launch
each app to finish setup. Choose Apple Silicon or a universal build when offered.

| App | Download |
| --- | --- |
| ChatGPT | [macOS desktop app](https://learn.chatgpt.com/docs/app) |
| Helium | [Helium](https://helium.computer/) |
| Steam | [Steam for macOS](https://store.steampowered.com/about/) |
| Raycast | [Raycast](https://www.raycast.com/) |
| OpenLogi | [Signed macOS DMG](https://github.com/AprilNEA/OpenLogi/releases/latest) |
| Tailscale | [Standalone macOS app](https://tailscale.com/download/mac) |

Use the apps' own update settings. Helium services must be enabled for its
updater. OpenLogi's update checks are opt-in; newer releases can be installed
from the same download page.

Set Helium as the default browser and enable Raycast at login. OpenLogi supports
the MX Master 3 and 4 receivers. Grant OpenLogi Agent Accessibility and Input
Monitoring, then check buttons, thumb wheel, and SmartShift. Quit Options+ if
present before using OpenLogi, since they compete for receiver access.

## Apply dotfiles

Install Apple's Command Line Tools with `xcode-select --install`, then install
[Determinate Nix](https://determinate.systems/nix/). Determinate owns the Nix
daemon; this host sets `nix.enable = false`.

```bash
mkdir -p ~/projects
git clone https://github.com/averagechris/dotfiles.git ~/projects/dotfiles
cd ~/projects/dotfiles
git switch chris/personal-darwin-host # Before PR merge; use main afterward.
nix run .#setup-darwin-determinate-substituters
nix run .#darwinConfigurations.taro.pkgs.nh -- darwin build -q --no-nom . --hostname taro
nix run .#darwinConfigurations.taro.pkgs.nh -- darwin switch . --hostname taro
```

Run these commands on taro. The cache setup uses sudo and restarts Determinate's
daemon. See [daemon settings](suremac.md#determinate-nix-daemon-settings) for its
settings and recovery tradeoff. After activation, use:

```bash
nh darwin switch . --hostname taro
```

Log out and back in if Colemak-DH is not visible. Keep U.S. as a fallback input
source. Follow the [App Management guide](troubleshooting/home-manager-app-management.md)
if Home Manager needs macOS permission.

Git and jj use `Chris Cummings <chris@thesogu.com>`. Signing is disabled until a
personal key is enrolled. First activation needs no encrypted secrets. Personal
projects live under `~/projects` and `~/contrib`.

## LAN SSH

The custom sshd accepts public keys for `chris` on port 2222. After taro's first
activation, apply this revision on suremac and run `nix run .#pair-taro` there.
Pairing creates taro's key if needed, authorizes its public key on suremac, and
checks the reverse connection. Enter a passphrase when creating a key and compare
taro's first-connection fingerprint using the [pairing instructions](lan-ssh.md#mac-to-mac-access).

Once paired:

```bash
# From suremac
ssh taro-lan hostname
# From taro
ssh suremac-lan hostname
```

The aliases use `taro.local` and `suremac.local`, so both Macs must be on the same
LAN. See [Mac-to-Mac key enrollment](lan-ssh.md#mac-to-mac-access) for public keys,
first-connection verification, and the required suremac activation.

## Join the personal tailnet

1. Install and open the standalone Tailscale app from the download list.
2. Approve its network extension and VPN configuration in System Settings.
3. Sign in with the identity for your existing personal tailnet and enable login
   startup. Confirm the selected network in the app.
4. Set the device name and verify the connection:

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale set --hostname=taro
/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json \
  | jq '{state: .BackendState, tailnet: .CurrentTailnet.Name, name: .Self.HostName}'
```

Expect `Running`, your personal tailnet's name, and `taro`. Complete device
approval in the personal tailnet's admin console if required. Enrollment uses
interactive login; no auth key is stored in dotfiles. Follow the
[macOS installation guide](https://tailscale.com/docs/install/mac) if an extension
prompt needs attention.

Other devices on that tailnet can use `ssh -p 2222 chris@taro` when MagicDNS and
the tailnet's access rules allow it. The LAN aliases remain independent of
Tailscale membership.

## Plugged-in work

Activation sets `pmset -c sleep 0`. AC idle system sleep is disabled; battery and
display sleep settings are preserved. Verify with `pmset -g custom`.

Keep the lid open or use a supported powered external display. Lid closure,
manual sleep, reboot, and FileVault unlock can interrupt access. The Tailscale
app and GUI agents need a logged-in user session. See [dev-cache](dev-cache.md)
for build-cache cleanup.
