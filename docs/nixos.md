# Installation

This is based on the installation guide in the [nixos manual](https://nixos.org/manual/nixos/stable/index.html#version-21-05)
supplemented with the tips in [this fantastic blog post](https://qfpl.io/posts/installing-nixos/).

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
> We’ll refer to it as `$LVM_PARTITION` below. Note that our boot partition won’t
> be encrypted. I can’t think of a reason why you would want this, and if you did,
> you probably wouldn't need partitioning advice from me. Also note that our swap
> partition is encrypted. You don’t have any control over what’s moved into your
> swap space, so it could end up containing all sorts of private stuff in the clear
> - for example passwords copied from a password manager

NOTE: In the example below a swap of 32GB s created. But you can create whatever
size you want.

``` shell
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

``` shell
# make the boot partition a FAT32 file system
mkfs.vfat -n boot $BOOT_PARTITION  # e.g. /dev/sda1 or /dev/nvme0n1p1

# make the root partition file system
mkfs.ext4 -L nixos /dev/nixos-vg/root

# making the swap partition a swap 
mkswap -L swap /dev/nixos-vg/swap
swapon /dev/nixos-vg/swap
```

### Generate the base NixOS Configuration
The installation NixOs provides a command to generate a base nix configuration with
some useful defaults and some hardware-detection baked in. But before we run that,
we have to mount the file systems.

``` shell
# mounting
mount /dev/nixos-vg/root /mnt
mount /mnt/boot
mount $BOOT_PARTITION /mnt/boot

# generating initial config
nixos-generate-config --root /mnt
```

### Required Configuration Changes
The shell you're in has a few different text editors already installed that you can
use. But thankfully, since this is nix, you can use `nix-shell -p` to get a shell
with whatever editor you want to use to make these quick config changes.

Open up `/mnt/etc/nixos/configuration.nix` with your text editor.

> Remember, you should still be logged in as root here.

You configure NixOs to work with the encrypted drive by adding it to the `configuration.nix`.
Add the following and feel free to un-comment any of the default stuff provided that
makes sense, like the timezone setting etc.

``` nix
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

### Finish Installation

```shell
# NOTE: this prompts you to set the root password now
nixos-install
```

It'll take a little while for everything to install. So take a break! Afterward,
once you've defined your root password you'll need to reboot.

``` shell
reboot
```

If anything goes wrong, you can boot back into the usb live media, mount your partitions
and edit the configuration.

``` shell
cryptsetup luksOpen $LVM_PARTITION nixos-enc

lvscan

vgchange -ay

mount /dev/nixos-vg/root /mnt

# do whatever you need to, like editing the `configuration.nix`
```

> 💡 Tip: if you do forget your root password, you _can_ reset it by booting back
> into the usb live media and using [nixos-enter](https://nixos.wiki/wiki/Change_root).
> Then use the `passwd` command to reset the root password.

## Getting my NixOs config from dotfiles and setting up Home Manager

👍😎👍 TODO
