{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/desktop_common.nix
    ../nixpkgs/nixos/graphical.nix
    ../nixpkgs/nixos/greetd.nix
    ../nixpkgs/nixos/networking.nix
    ../nixpkgs/nixos/docker.nix
    ../nixpkgs/nixos/sound.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/users/chris.nix
    ./hardware-configurations/thelio.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
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
  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  hardware.enableRedistributableFirmware = true;
  hardware.system76.enableAll = true;
  programs.steam.enable = true;

  system.stateVersion = "21.05";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "21.05";
    dotfiles.gui.enable = true;
    programs.meganz.enable = true;

    dotfiles.gui.sway.enable = false;
    dotfiles.gui.hyprland.enable = true;
    dotfiles.shell.python.enable = true;
    programs.obsidian.enable = false;
    programs.helix.package = inputs.helix.packages.x86_64-linux.default;
  };
}
