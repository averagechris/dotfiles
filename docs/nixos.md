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
