{ config, pkgs, lib, ... }:

let
  primaryDisk = "/dev/nvme0n1p2";
  computerName = "xps-nixos";

in
{
  imports =
    [
      <nixos-hardware/dell/xps/13-9310>
      /etc/nixos/hardware-configuration.nix
      ../common.nix
      ../greetd.nix
      ../networking.nix
      ../sound.nix
      ../users.nix
    ];

  boot.initrd.luks.devices.root.device = primaryDisk;
  networking.hostName = computerName;

  networking.wireless.interfaces = [ "wlp0s20f3" ];
  networking.interfaces.wlp0s20f3.useDHCP = true;

  system.stateVersion = "21.05";
}
