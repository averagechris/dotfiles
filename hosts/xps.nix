{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/desktop_common.nix
    ../nixpkgs/nixos/docker.nix
    ../nixpkgs/nixos/graphical.nix
    ../nixpkgs/nixos/greetd.nix
    ../nixpkgs/nixos/networking.nix
    ../nixpkgs/nixos/sound.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/users/chris.nix
    ./hardware-configurations/xps.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.dell-xps-13-9310
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    }
  ];

  boot.initrd.luks.devices.root.device = "/dev/nvme0n1p2";
  networking.hostName = "xps-nixos";

  networking.wireless.interfaces = ["wlp0s20f3"];
  networking.interfaces.wlp0s20f3.useDHCP = true;

  # these opengl is needed for sway to work right on intel graphics
  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;

  system.stateVersion = "21.05";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "21.05";
  };

  boot.kernelModules = [
    "ipt_dnat"
    "ipt_mark"
    "iptable_filter"
    "iptable_nat"
    "sch_cake"
    "xt_nat"
  ];
}
