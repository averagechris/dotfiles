{ config, pkgs, lib, ... }:

let
  primaryDisk = "/dev/sda2";
  computerName = "thelio-nixos";

in
{
  imports =
    [
      <nixos-hardware/system76>
      /etc/nixos/hardware-configuration.nix
      ../common.nix
      ../greetd.nix
      ../gtk.nix
      ../networking.nix
      ../podman.nix
      ../sound.nix
      ../users.nix
    ];

  boot.initrd.luks.devices.root.device = primaryDisk;
  networking.hostName = computerName;

  networking.wireless.interfaces = [ "wlp6s0" ];
  networking.interfaces.enp5s0.useDHCP = true;
  networking.interfaces.enp7s0f3u4u3u4.useDHCP = true;
  networking.interfaces.wlp6s0.useDHCP = true;

  system.stateVersion = "21.05";

  # system76 doesn't use fwupd / fwupdmgr, they have their own cli
  environment.systemPackages = [ pkgs.system76-firmware ];
}
