# Personal MacBook Pro setup

`taro` is the nix-darwin host for the donated, factory-reset MacBook Pro. This guide covers its first activation and use as a personal laptop
that can also accept builds and automation over SSH.

## Machine details

Confirmed hardware and account details are Apple Silicon (`aarch64-darwin`),
48 GiB RAM, macOS 26.5.1 build 25F80, and short username `chris` with home
directory `/Users/chris`. The post-reset Bonjour name is
`Christophers-MacBook-Pro`; activation changes it to the configured hostname.
The chosen hostname is `taro`.

Helium, Steam, Raycast, and OpenLogi are installed directly from their official
downloads.
Automation jobs remain choices to confirm during onboarding.

## Bootstrap the wiped Mac

Prerequisites: completed macOS onboarding, an administrator account matching the
configuration, and Determinate Nix installed through its installer. This host sets
`nix.enable = false`, so Determinate owns the Nix daemon. Install Apple's Command
Line Tools with `xcode-select --install` for development outside Nix shells.

Clone the public repository over HTTPS until this Mac has its own GitHub SSH key.
Before the draft PR is merged, check out `chris/personal-darwin-host`; after merge,
use `main`:

```bash
mkdir -p ~/projects
git clone https://github.com/averagechris/dotfiles.git ~/projects/dotfiles
cd ~/projects/dotfiles
git switch chris/personal-darwin-host # Pre-merge only; use main after merge.
nix run .#setup-darwin-determinate-substituters
nix run .#darwinConfigurations.taro.pkgs.nh -- darwin build -q --no-nom . --hostname taro
nix run .#darwinConfigurations.taro.pkgs.nh -- darwin switch . --hostname taro
```

The cache setup command uses sudo and updates `/etc/nix/nix.custom.conf`, then
restarts Determinate's daemon. See [suremac's daemon settings](suremac.md#determinate-nix-daemon-settings)
for the settings and `fsync-metadata` crash-recovery tradeoff. Run the switch
command only on the new Mac. No activation of `suremac` is needed.

After activation, open a new terminal and use the installed `nh`:

```bash
nh darwin build -q --no-nom . --hostname taro
nh darwin switch . --hostname taro
```

The standalone flake also works with `./flakes/hosts/taro` in place of `.`.
Colemak-DH input sources may need a logout/login before appearing everywhere.
Keep the U.S. input source available as a fallback. Allow Home Manager's app
management permission if macOS requests it, following the
[App Management troubleshooting guide](troubleshooting/home-manager-app-management.md).

## Personal profile

The host uses personal Git and jj identity, `Chris Cummings <chris@thesogu.com>`,
and personal project directories `~/projects` and `~/contrib`. It explicitly clears
the shared jj module's historical Sure directory scope. The shell, Helix, Yazi,
WezTerm, Gander, Codex, OpenCode, Pi, and memo are configured for personal use.

No agenix secrets are required for first activation. Git and jj signing start
disabled until a personal signing key is enrolled. Sign into coding agents using
personal accounts; no work OpenRouter key, Granola token, AWS profiles, Kubernetes
contexts, Sure agent references, or work hygiene jobs are installed. The config
does not install suremac's self-update job. macOS security-update preferences stay
at the machine's existing defaults.

See [dev-cache](dev-cache.md) for build-cache cleanup behavior.

## Native apps and self-updates

On taro, install these apps directly from upstream. Their ordinary app bundles
live in `/Applications`. Helium, Steam, and Raycast update themselves; OpenLogi
uses optional update checks and manually downloaded releases as described below.
No package manager or pinned download version is involved.

| App | Official download |
| --- | --- |
| Helium | [Helium browser](https://helium.computer/) |
| Steam | [Steam for macOS](https://store.steampowered.com/about/) |
| Raycast | [Raycast](https://www.raycast.com/) |
| OpenLogi | [Signed macOS DMG](https://github.com/AprilNEA/OpenLogi/releases/latest) |

An agent can perform the installation with the browser or command-line download
tools, following the same steps as an interactive install:

1. Open the official page and follow its current macOS download link. Choose
   Apple Silicon or ARM64 when offered; use a universal build otherwise.
2. Download and open the disk image or archive, then copy the app bundle to
   `/Applications`. Follow the official installer if it uses a different format.
3. Open the installed app to finish its first-run setup. Enable automatic updates
   if prompted, and use personal accounts for sign-in.
4. Eject the disk image and remove the downloaded installer after confirming the
   installed app opens.

Keep Helium services enabled for its automatic updater, as described in the
[Helium FAQ](https://helium.computer/). Set Helium as the default browser and
choose Raycast's login startup and shortcuts in their own settings. Verify that
`Helium.app`, `Steam.app`, `Raycast.app`, and `OpenLogi.app` open from
`/Applications`. Repeat the download steps for a reinstall.

### Logitech setup

Use [OpenLogi](https://openlogi.org/) for Logitech configuration instead of
Logi Options+.
Its [supported-device list](https://openlogi.org/docs/supported-devices) includes
Chris's MX Master 3 and MX Master 4, with support for Unifying and Bolt receivers.
The project is still marked unstable; trial one mouse before configuring both.

Download the signed, notarized macOS DMG from the
[official releases](https://github.com/AprilNEA/OpenLogi/releases/latest) and copy
`OpenLogi.app` to `/Applications`. Follow its
[macOS installation instructions](https://openlogi.org/docs/installation), granting
OpenLogi Agent Accessibility and Input Monitoring when prompted. Quit Options+
if present before launching OpenLogi, since they compete for receiver access.
Verify side buttons, the thumb wheel, gestures, DPI, and SmartShift on each mouse.

The project documents no account or telemetry, with local configuration in
`~/.config/openlogi/config.toml`. Its [network disclosure](https://openlogi.org/#privacy)
lists device artwork fetched from a public CDN and optional update checks, off
by default. Keep update checks off for a manual-update trial; install newer DMGs
from the release page. This privacy description comes from the project, not an
independent audit.

## Desktop choices

Use macOS floating windows and Raycast for window management. AeroSpace and Stats
are not part of this setup. Homerow is not selected because it requires payment.
BetterDisplay remains an optional evaluation, outside the main download list.
Its [free/Pro comparison](https://betterdisplay.pro/guide/licensing/free-and-pro-features/)
identifies which display controls remain available without Pro after the trial.

## Container runtime experiments

A container runtime is not part of the download list or nix-darwin configuration.
Try Apple's [container CLI](https://github.com/apple/container) before deciding
whether to bring over [OrbStack](https://orbstack.dev/), which Chris already uses
on suremac. OrbStack remains an option for later.

Apple's CLI runs OCI-compatible Linux containers in lightweight VMs using its
[Containerization library](https://github.com/apple/containerization). It supports
Apple Silicon and macOS 26, matching taro. When ready to experiment, use the
latest signed `.pkg` from the [official releases](https://github.com/apple/container/releases),
following the upstream installation instructions. A first smoke check is:

```bash
container system start
container run --rm alpine echo hello
```

The expected output is `hello`. Before choosing a runtime for automation, try a
representative personal project and check image builds, bind mounts, networking,
and its orchestration requirements. Use the upstream `container` commands during
the trial rather than assuming existing Docker-specific scripts are compatible.

## SSH and plugged-in work

The shared custom SSH service listens on TCP 2222 using Apple's sshd. It allows
only `chris`, accepts public keys, and disables password and keyboard-interactive
authentication. It reads nix-darwin's declarative key file as well as the user's
`~/.ssh/authorized_keys`. It authorizes thorny's `chris.thelio` user key and
tater's system key for automation that explicitly uses that identity. The standard Remote Login
service on port 22 is disabled by this profile.

After activation, read the fresh host key directly on the new Mac:

```bash
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

Verify that key through a trusted channel before accepting it on another machine.
Then connect from thorny using the Mac's current home LAN IP or its Bonjour name:

```bash
ssh -p 2222 chris@taro.local hostname
ssh -p 2222 chris@taro.local 'nix config show system'
```

Expected results are `taro` and `aarch64-darwin`. Remote Login being off in
System Settings is expected; this is a separate launchd service. Inspect
`sudo launchctl print system/org.nixos.dotfiles-custom-sshd` and
`/var/log/dotfiles-custom-sshd.log` if it fails to start.

The existing `ssh-lan` fleet discovery helpers use port 22 and committed host
keys. They cannot discover `taro` yet. Do not copy suremac's old host key or
private identities onto this wiped Mac. It needs its own user key for outbound
SSH; enrolling its public user/host keys and configuring remote builders are
follow-up steps once the real keys and CPU capacity are known.

On AC power, activation applies `pmset -c sleep 0` so idle display sleep does not
interrupt jobs. Battery and display sleep settings are preserved. Verify with
`pmset -g custom`: AC Power should show `sleep 0`; battery policy should remain
unchanged. To restore automatic AC sleep, apply `pmset -c sleep 10` before removing
the managed activation command, since pmset settings persist.

Lid closure, manual sleep, reboot, and FileVault's pre-login unlock can still make
this laptop unavailable. Use an open lid or a supported powered external-display
setup. SSH starts at boot, but GUI agent sessions need the user logged in. AC
power keeps it awake on any network, not just at home. No scheduled
build worker, CI runner, wake schedule, or unattended GUI automation is enrolled
by this draft.
