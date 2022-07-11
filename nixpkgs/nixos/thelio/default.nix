{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.initrd.luks.devices.root.device = "/dev/sda2";
  networking.hostName = "thelio-nixos";

  networking.wireless.interfaces = ["wlp6s0"];

  # dhcp and network manager are causinng issues
  # https://github.com/NixOS/nixpkgs/issues/152288
  networking.interfaces.enp5s0.useDHCP = true;
  networking.interfaces.enp7s0f3u4u3u4.useDHCP = true;
  networking.interfaces.wlp6s0.useDHCP = true;

  # system76 doesn't use fwupd / fwupdmgr, they have their own cli
  environment.systemPackages = [pkgs.system76-firmware];
  programs.steam.enable = true;

  virtualisation.virtualbox.host.enable = false;
  virtualisation.virtualbox.host.enableWebService = false;

  system.stateVersion = "21.05";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "21.05";
  };
}
