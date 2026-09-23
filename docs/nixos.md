# Installation

This is based on the installation guide in the [nixos manual](https://nixos.org/manual/nixos/stable/index.html#version-21-05)
supplemented with the tips in [this blog post](https://qfpl.io/posts/installing-nixos/).

## Shared CLI tools

All NixOS hosts import `nixosModules.common`, which installs common Nix and
editing tools including `nh` and `nix-output-monitor` (`nom`).

- `nom` is a more readable progress UI for supported Nix commands:
  `nom build .#pkg`, `nom develop`, `nom shell nixpkgs#ripgrep`.
  Use `nix flake check` for flake checks; this `nom` wrapper does not support
  `nom flake check`.
- `nh` wraps common NixOS workflows:
  `nh os build . --hostname tater`, `nh os test . --hostname tater`,
  `nh os switch . --hostname tater`.

Prefer `nh` for NixOS build/test/switch commands and `nom` for supported raw Nix
commands in this repository. Use `nix flake check` for flake checks. These
wrappers keep long Nix output readable and make failure context easier to find
than plain `nix`/`nixos-rebuild` output where supported. Use lower-level
commands only when needed for a specific flag or reproduction.

## Validation tiers

Use the smallest validation tier that matches the change, then escalate
deliberately when host behavior or fleet coverage matters:

- `jj lint` is the normal agent/developer handoff gate. It runs the
  repository-configured lint bundle for the current change and should remain the
  first inner-loop command before pushing or handing off work.
- Target/shared eval-only checks verify flake structure without realizing build
  outputs. Use `nix flake check --accept-flake-config --no-build
  ./flakes/<shared-flake>` for shared flakes and `nix flake check
  --accept-flake-config --no-build ./flakes/hosts/<hostname>` for a specific
  host. Add `--no-write-lock-file` in automation so validation never mutates a
  checkout lock. This catches evaluation and check-definition failures cheaply.
- Target host builds realize one host closure when you need build confidence:
  `nh os build -q --no-nom . --hostname <hostname>` for NixOS, or
  `nh darwin build -q --no-nom . --hostname suremac` for Darwin. These are
  intentionally narrower than a root fleet check.
- Explicit full-fleet validation is `nix flake check --accept-flake-config` at
  the root. It evaluates and builds the aggregate fleet checks, which is too
  expensive for the ordinary CI path.

GitHub Actions mirrors those tiers with three bounded jobs on pull requests and
pushes to `main`:

- `fast` runs `scripts/ci-check-tiers.sh fast` inside the repository dev shell:
  formatting,
  Statix, ShellCheck, and shared flake eval-only checks.
- `active-host-evals` runs `scripts/ci-check-tiers.sh
  active-host-evals`: active NixOS hosts `trap`, `thorny`, `tom`, `cruber`,
  `tater`, and `trainwreck` evaluate drvPaths sequentially in separate Nix
  processes with no builds, no lock writes, and eval cache disabled. Routine CI
  does not realize full host closures because they exceed practical hosted
  runner disk headroom. Inactive `taz` and `tootsie` are excluded.
- `coverage-checks` runs on x86_64 Linux: it
  evaluates suremac's Darwin system only and builds selected high-signal desktop
  check derivations for tater and thorny. suremac remains eval-only because
  realizing the Darwin closure on Linux is not useful CI coverage for this repo.

Heavyweight or diagnostic paths remain manual local commands: run
`scripts/ci-check-tiers.sh full-fleet`, run `trainwreck-build` natively on
aarch64 Linux, and perform trap disk/cache diagnostics only when investigating a
specific problem. Thorny remains the operational full-closure builder/cache warmer.
See [cache policy](/docs/cache-policy.md) for the per-environment cache/key/
builder matrix and publication policy.

Every CI Nix command passes `--no-write-lock-file`; eval-only commands use
`--raw` and disable the eval cache where that keeps repeated host evaluation
comparable. The GitHub workflow has read-only repository permissions, uses no
secrets, and does not push cache outputs. The fast path runs ShellCheck over
tracked `*.sh` files reported by jj when available, with Git as the CI checkout
fallback; it does not invoke `jj lint` directly, but covers the important
shell-script linting that `jj lint` also runs locally.

For captured/noninteractive logs, use `nh -q --no-nom` commands, such as
`nh os build -q --no-nom . --hostname tater`, so the `nom` clock/progress
animation and most store-path chatter do not repeat in captured output.

The Darwin host also installs these tools directly in its host configuration.

`nixosModules.common` installs `gitMinimal` rather than full `git`. This covers
normal CLI Git, fetch/clone operations used by Nix helper scripts, signing, and
jj interoperability without retaining optional full-Git runtime dependencies in
every host system closure. The shared Home Manager Git module also avoids
installing Delta, lazygit, or custom Git branch aliases by default now that jj is
the daily VCS interface. Use full `pkgs.git`, a Git TUI, or extra Git aliases
only on hosts or scripts that need a specific non-minimal Git workflow.

Minimal server hosts should opt out of the shared Home Manager shell profile when
they do not need an interactive workstation toolchain. The shell profile brings
Helix, Yazi, lazygit, jj, Starship, and related CLI helpers; that is useful on
workstations but excessive for narrow service hosts. `tom`, `taz`, and `tootsie`
therefore set:

```nix
home-manager.users.chris.dotfiles.shell.enable = false;
home-manager.users.chris.dotfiles.gpg.enable = false;
```

Keep server-specific tools in `environment.systemPackages`, service packages, or
small host-local Home Manager package lists instead of re-enabling the full shell
profile by default. Disable the GPG signing helper on servers that do not have
the matching agenix key material or do not make signed commits locally.

## Local generated option documentation

The shared NixOS common module disables generated NixOS documentation with
`documentation.nixos.enable = false`. These configs do not normally use local
`nixos-help`, `configuration.nix(5)`, or the generated offline NixOS options
JSON, and disabling them keeps `nix flake check` from evaluating the option-doc
generator for every host.

The shared `chrisMinimal` NixOS user module also disables generated Home Manager
manpages with `manual.manpages.enable = false`, because that Home Manager manual
path uses the same option-doc generator and is the source of the `options.json`
warning during system evaluation.

If an agent or debugging session needs those local docs, temporarily re-enable
them in a host config or an ad-hoc module:

```nix
{
  documentation.nixos.enable = true;

  home-manager.users.chris.manual.manpages.enable = true;
}
```

## Flake check warnings

`nix flake check` may still print warnings that come from outside this
repository's Nix modules:

- `Copying ... to the store again` warnings for upstream flakes that package
  themselves with `./.`. Fixing those requires changing the referenced upstream
  flake, not this aggregator.
- `unknown flake output 'deploy'` for the deploy-rs `deploy.nodes` output. This
  output is intentionally kept because `nix run .#deploy -- .#<hostname>` and
  deploy-rs tooling consume it.
- `The check omitted these incompatible systems` when checking from a single
  platform. Use `nix flake check --all-systems` only when you intentionally want
  to evaluate every declared system.

## Graphical host post-install checklist

For any new graphical workstation host, configure KeePassXC's native tray behavior
before relying on Hyprland/Eww password-manager bindings:

- enable **show system tray icon**
- enable **minimize to tray**
- enable **close to tray** / **minimize instead of exiting on close**

The Hyprland `hctl hide keepassxc` workflow sends KeePassXC a normal close
request and expects KeePassXC to convert that into a tray hide. Without these
KeePassXC settings, close-style bindings can quit the app instead of hiding it.

## Create installation media

> Any iso provided by the [NixOS Download Page](https://nixos.org/nixos/download.html)
> should work just fine.  But I have only done this with the 64bit minimal iso.

**tl;dr;**
Copy the iso to the USB disk. Use `lsblk` to identify it.

```shell
dd if=$INSTALLER_ISO of=$DISK bs=1M
```

The [NixOs installation media docs](https://nixos.wiki/wiki/NixOS_Installation_Guide#Making_the_installation_media)
have a more detailed guide and provide alternative methods.

## Tweak BIOS settings

- Ensure safe boot is disabled
- Ensure UEFI mode is enabled

## Installing NixOS from the live USB

Boot from the USB. For all of my machines this means pressing `f12` and choosing
the USB disk as the boot disk from the BIOS menu. The key to press can differ
depending on the hardware brand.

NixOS will show a splash screen for a few seconds while it's setting up, then drop
you into a shell with root logged in, or if using a graphical iso, into a desktop
environment.

> NOTE: that shell commands from here should be run as root

### Optionally connect to WiFi

You need an internet connection. If you can't connect to the internet via ethernet,
you can connect via WiFi.

Setup the WiFi credentials

```shell
wpa_passphrase $SSID $PASSPHRASE > /etc/wpa_supplicant.conf
```

Restart the WiFi service

```shell
systemctl restart wpa_supplicant.service
```

### Partitioning the disk

You need to make a boot partition and a root partition (a partition for all of your
data). To do so use the `gdisk` command to make a GPT (assuming UEFI).

Run `lsblk` to identify the disk you want to install NixOs to. It'll be named something
like `/dev/sda` or `/dev/nvme0n1`.

Delete all of the existing partitions and data.

```shell
# NOTE: Replace $DISK with the disk you want to install NixOs to.
gdisk $DISK

# --- below here is a gdisk prompt

# print the partitions already on the disk
Command: p

# delete a parition, repeating this for each partition
Command: d
```

Now, staying at the same `gdisk` prompt, you need to create the boot and root partitions.

```shell
# create the EFI boot partition
Command: n
Partition number: 1
First sector: # press enter to use the default
Last sector: +1G  # makes this a 1 gig partition
Hex code or GUID: ef00 # the hexcode representing the EFI System type

# create the LVM partition (used for your data)
Command: n
Partition number: 2
First sector: # press enter to use the default
Last sector:  # press enter to use the default (the rest of the available space)
Hex code or GUID: 8e00 # the hexcode representing the Linux LVM type

# [OPTIONAL] give each of these partitions a name
# making them easy to refer to in configurations later
# instead of by uuid.
Command: c
Partition number: 1
Name: NIXOS_BOOT

Command: c
Partition number: 2
Name: NIXOS_ROOT

# [OPTIONAL] review the commands that gdisk will write out
Command: p

# have gdisk apply the changes then quit
Command: w
```

### Encrypting the disk

The blog post I linked at the top of these docs explains the thought process behind
encryption and swap well. Here's a direct quote.

> Our partition table and primary partitions are in place. Now we can encrypt the
> partition that will contain our LVM partitions. This is the second partition that
> we created above - so should be something like `/dev/nvme0n1p2` or `/dev/sda2.`
> We'll refer to it as `$LVM_PARTITION` below. Note that our boot partition won't
> be encrypted. I can't think of a reason why you would want this, and if you did,
> you probably wouldn't need partitioning advice from me. Also note that our swap
> partition is encrypted. You don't have any control over what's moved into your
> swap space, so it could end up containing all sorts of private stuff in the clear
>
> - for example passwords copied from a password manager
>
> NOTE: In the example below a swap of 32GB is created. But you can create whatever
> size you want.

```shell
# NOTE the command below will prompt you for a passphrase
# REMEMBER IT! If you forget it, you'll have to start over.
# this encrypts the partition with the passphrase you give
cryptsetup luksFormat $LVM_PARTITION

# now decrypt the parition and give it a name `nixos-enc`
# the decrypted partition will be mounted at /dev/wrapper/nixos-enc
cryptsetup luksOpen $LVM_PARTITION nixos-enc

# create a volume group (for root & swap)
vgcreate nixos-vg /dev/mapper/nixos-enc

# create the swap partition, labeled `swap`
lvcreate -L 32G -n swap nixos-vg

# create a logical volume for the root filesystem
lvcreate -l '100%FREE' -n root nixos-vg
```

### Create the filesystem

```shell
# make the boot partition a FAT32 file system
mkfs.vfat -n boot $BOOT_PARTITION  # e.g. /dev/sda1 or /dev/nvme0n1p1

# make the root partition file system
mkfs.ext4 -L nixos /dev/nixos-vg/root

# making the swap partition a swap
mkswap -L swap /dev/nixos-vg/swap
swapon /dev/nixos-vg/swap
```

### Generate the base NixOS configuration

The installation NixOs provides a command to generate a base nix configuration with
some useful defaults and some hardware-detection baked in. But before we run that,
we have to mount the file systems.

```shell
# mounting
mount /dev/nixos-vg/root /mnt
mount /mnt/boot
mount $BOOT_PARTITION /mnt/boot

# generating initial config
nixos-generate-config --root /mnt
```

### Required configuration changes

The shell you're in has a few different text editors already installed that you can
use. But thankfully, since this is nix, you can use `nix-shell -p` to get a shell
with whatever editor you want to use to make these quick config changes.

Open up `/mnt/etc/nixos/configuration.nix` with your text editor.

> Remember, you should still be logged in as root here.

You configure NixOs to work with the encrypted drive by adding it to the `configuration.nix`.
Add the following and feel free to un-comment any of the default stuff provided that
makes sense, like the timezone setting etc.

The shared desktop module sets `time.timeZone = lib.mkDefault "America/Los_Angeles"`
and enables `systemd-timesyncd` with internet NTP servers (`time.cloudflare.com`,
`time.google.com`, `pool.ntp.org`, plus NixOS pool fallbacks). After boot or
network changes, check clock synchronization with:

```shell
timedatectl timesync-status
timedatectl status
```

On laptops such as `tater`, `services.automatic-timezoned.enable = true` keeps
the timezone location-aware while traveling. It uses geoclue2 to determine the
current location and systemd-timedated to update the timezone. When this service
is enabled, NixOS intentionally leaves `time.timeZone = null` so the runtime
timezone can be managed dynamically rather than pinned by the declarative config.

```nix
# in /mnt/etc/nixos/configuration.nix

# ... snip ...

boot.initrd.luks.devices = {
  root = {
    # TODO can we use by label here?
    device = "$LVM_PARTITION";  # e.g. /dev/sda2 or /dev/nvme0n1p2
    preLVM = true;
  };
};

# you might find that NixOs included this in the generated config, but if not
# include it here
boot.loader.systemd-boot.enable = true;

# define your user
users.users.chris = {
  isNormalUser = true;
  extraGroups = [ "wheel" ]; # Enable `sudo` for the user.
  shell = pkgs.zsh;
};

# install a bare minimum set of packages available to all users
# remember: most packages should be installed for your user via
# home-manager
environment.systemPackages = with pkgs; [
  git
  nix-prefetch-scripts  # https://github.com/msteen/nix-prefetch/
  neovim
  which
];
```

### Finish installation

> NOTE: this prompts you to set the root password now

```shell
nixos-install
```

It'll take a little while for everything to install. So take a break! Afterward,
once you've defined your root password you'll need to reboot.

```shell
reboot
```

If anything goes wrong, you can boot back into the usb live media, mount your partitions
and edit the configuration.

```shell
cryptsetup luksOpen $LVM_PARTITION nixos-enc

lvscan

vgchange -ay

mount /dev/nixos-vg/root /mnt

# do whatever you need to, like editing the `configuration.nix`
```

> Tip: if you do forget your root password, you _can_ reset it by booting back
> into the usb live media and using [nixos-enter](https://nixos.wiki/wiki/Change_root).
> Then use the `passwd` command to reset the root password.

## Applying dotfiles configuration

After installation, clone the dotfiles repo and apply:

```bash
git clone https://github.com/averagechris/dotfiles ~/dotfiles
cd ~/dotfiles
nixos-rebuild switch --use-remote-sudo --flake .#HOSTNAME
```

## Home Manager state version notes

### 26.05 changes

The dotfiles use `home.stateVersion = "26.05"` across all hosts. Key changes from previous versions:

- GTK4 theme: `gtk.gtk4.theme` no longer mirrors `gtk.theme` automatically. If you use custom GTK themes and want them applied to GTK4 applications (like modern GNOME apps), you must explicitly set:
  ```nix
  gtk.gtk4.theme = config.gtk.theme;
  ```
  See [Home Manager issue #6325](https://github.com/nix-community/home-manager/issues/6325) for context. GTK4 theming is not officially supported and uses a workaround that may cause issues with some applications.

- Zsh dotDir: With `xdg.enable = true`, zsh config now defaults to `~/.config/zsh/` instead of `~`. This keeps your home directory cleaner.

- Yazi wrapper: The shell wrapper function changed from `yy` to `y`. This repository explicitly sets `programs.yazi.shellWrapperName = "yy"` to preserve the old behavior.

- Git signing format: For GPG signing, `programs.git.signing.format` no longer defaults to `"openpgp"`. This repository explicitly sets it for GPG users.

- XDG user dirs: `xdg.userDirs.setSessionVariables` now defaults to `false` instead of `true`.
