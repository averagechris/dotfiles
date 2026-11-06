# Personal MacBook Pro setup

`taro` is the nix-darwin host for the donated, factory-reset MacBook Pro. This guide covers its first activation and use as a personal laptop
that can also accept builds and automation over SSH.

## Machine details

Confirmed hardware and account details are Apple Silicon (`aarch64-darwin`),
48 GiB RAM, macOS 26.5.1 build 25F80, and short username `chris` with home
directory `/Users/chris`. The post-reset Bonjour name is
`Christophers-MacBook-Pro`; activation changes it to the configured hostname.
The chosen hostname is `taro`.

Installed native apps and automation jobs remain choices to confirm during
onboarding.

## Bootstrap the wiped Mac

Prerequisites: completed macOS onboarding, an administrator account matching the
configuration, and Determinate Nix installed through its installer. This host sets
`nix.enable = false`, so Determinate owns the Nix daemon. Install Apple's Command
Line Tools with `xcode-select --install` for development outside Nix shells.

Clone the public repository over HTTPS until this Mac has its own GitHub SSH key.
Before the draft PR is merged, check out `chris/personal-darwin-host`; after merge,
use `main`:

```bash
git clone https://github.com/averagechris/dotfiles.git ~/dotfiles
cd ~/dotfiles
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
WezTerm, Gander, Codex, OpenCode, Pi, memo, and ctx are configured for personal use.

No agenix secrets are required for first activation. Git and jj signing start
disabled until a personal signing key is enrolled. Sign into coding agents using
personal accounts; no work OpenRouter key, Granola token, AWS profiles, Kubernetes
contexts, Sure agent references, or work hygiene jobs are installed. The config
does not install suremac's self-update job. macOS security-update preferences stay
at the machine's existing defaults.

Native apps such as Helium, Raycast, and a container runtime can be installed
manually as needed, using personal accounts. The host does not rely on an MDM
software portal. See [dev-cache](dev-cache.md) for build-cache cleanup behavior.

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
setup. SSH starts at boot, but GUI agent sessions and ctx indexing need the user
logged in. AC power keeps it awake on any network, not just at home. No scheduled
build worker, CI runner, wake schedule, or unattended GUI automation is enrolled
by this draft.
